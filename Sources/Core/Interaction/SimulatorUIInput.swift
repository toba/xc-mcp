import MCP
import AppKit
import Foundation
import CoreGraphics

/// Errors raised while driving simulator UI input from the host.
public enum SimulatorUIInputError: LocalizedError, Sendable, MCPErrorConvertible {
    /// No booted simulator matched the given UDID or name.
    case notBooted(String)
    /// The Simulator window for the device could not be found on screen.
    case windowNotFound(String)
    /// The device screen rectangle could not be located inside the window.
    case screenNotDetected(String)
    /// A hardware button / menu action is not available via host automation.
    case unsupportedButton(String)
    /// An AppleScript / CGEvent step failed.
    case actionFailed(String)

    public var errorDescription: String? {
        switch self {
            case let .notBooted(name):
                "Simulator '\(name)' is not booted. Boot it with boot_sim and open the Simulator app."
            case let .windowNotFound(name):
                "No Simulator window found for '\(name)'. Open the Simulator app so its window is "
                    + "visible (host-side UI input drives the on-screen window). Also ensure Screen "
                    + "Recording permission is granted in System Settings > Privacy & Security."
            case let .screenNotDetected(detail):
                "Could not locate the device screen inside the Simulator window (\(detail)). The "
                    + "window may be occluded, minimized, or the app content may be edge-to-edge "
                    + "black. Bring the Simulator window fully on-screen and try again."
            case let .unsupportedButton(name):
                "Button '\(name)' cannot be triggered via host automation. Supported: home, lock, "
                    + "siri, shake, screenshot, rotate_left, rotate_right."
            case let .actionFailed(detail):
                "Simulator input failed: \(detail). Grant Accessibility permission in System "
                    + "Settings > Privacy & Security > Accessibility for this app."
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case .notBooted, .unsupportedButton: .invalidParams(errorDescription ?? "Invalid input")
            default: .internalError(errorDescription ?? "Simulator input failed")
        }
    }
}

/// Drives UI input (tap / swipe / long press / type / keys / hardware buttons) on a **booted
/// simulator** by synthesizing host-level `CGEvent`s on the on-screen Simulator window.
///
/// `simctl io` has no input operations, so there is no public API for injecting touches into a
/// running Simulator. This controller locates the device's Simulator window via `CGWindowList`,
/// detects the device-screen rectangle inside it (the window includes a title bar and, by default,
/// a device bezel), maps device coordinates onto host screen coordinates, and posts mouse /
/// keyboard events. Hardware buttons are driven through the Simulator's *Device* menu via
/// AppleScript.
///
/// ## Coordinates
///
/// Tap / swipe / long-press coordinates are in **device pixels** — the same space as the image
/// returned by the `screenshot` tool (e.g. an iPhone 17 screenshot is 1206×2622). This lets an
/// agent read a coordinate straight off a screenshot and pass it through unchanged.
///
/// ## Requirements
///
/// - The Simulator app must be running with the device's window visible on screen.
/// - **Screen Recording** permission (to enumerate / capture the window) and **Accessibility**
///   permission (to post events and drive menus) must be granted to the host process.
public actor SimulatorUIInput {
    private let simctlRunner: SimctlRunner

    /// Cached device-screen pixel size keyed by UDID. Invalidated when the detected on-screen
    /// aspect ratio stops matching (e.g. after a rotation).
    private var pixelSizeCache: [String: CGSize] = [:]

    public init(simctlRunner: SimctlRunner = .init()) { self.simctlRunner = simctlRunner }

    // MARK: - Public API

    /// Taps once at the given device-pixel coordinate.
    public func tap(simulator: String, x: Double, y: Double) async throws {
        let geo = try await geometry(for: simulator)
        let point = geo.map(x: x, y: y)
        try await focusWindow(deviceName: geo.deviceName)
        postMouse(.mouseMoved, point)
        usleep(40_000)
        postMouse(.leftMouseDown, point)
        usleep(60_000)
        postMouse(.leftMouseUp, point)
    }

    /// Presses and holds at the given device-pixel coordinate for `duration` seconds.
    public func longPress(simulator: String, x: Double, y: Double, duration: Double) async throws {
        let geo = try await geometry(for: simulator)
        let point = geo.map(x: x, y: y)
        try await focusWindow(deviceName: geo.deviceName)
        postMouse(.mouseMoved, point)
        usleep(40_000)
        postMouse(.leftMouseDown, point)
        try await Task.sleep(for: .seconds(duration))
        postMouse(.leftMouseUp, point)
    }

    /// Swipes from one device-pixel coordinate to another over `duration` seconds.
    public func swipe(
        simulator: String,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        duration: Double,
    ) async throws {
        let geo = try await geometry(for: simulator)
        try await focusWindow(deviceName: geo.deviceName)
        try await drag(
            from: geo.map(x: startX, y: startY),
            to: geo.map(x: endX, y: endY),
            duration: duration,
        )
    }

    /// Swipes between fractional screen positions (each component in `0...1`). Used by gesture
    /// presets that are expressed relative to screen dimensions.
    public func swipeFraction(
        simulator: String,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        duration: Double,
    ) async throws {
        let geo = try await geometry(for: simulator)
        try await focusWindow(deviceName: geo.deviceName)
        try await drag(
            from: geo.mapFraction(fx: startX, fy: startY),
            to: geo.mapFraction(fx: endX, fy: endY),
            duration: duration,
        )
    }

    /// Types `text` into the focused field by posting hardware-keyboard keystrokes to the Simulator
    /// window. Connects the hardware keyboard first (so host keystrokes reach the focused iOS
    /// field) and maps each character to a US-layout keycode — ASCII only; unmapped characters are
    /// reported.
    public func typeText(simulator: String, text: String) async throws {
        let device = try await resolveBootedDevice(simulator)
        try await focusWindow(deviceName: device.name)
        try await ensureHardwareKeyboardConnected()
        var unsupported: [Character] = []

        for character in text {
            if !postCharacter(character) { unsupported.append(character) }
            usleep(8_000)
        }
        if !unsupported.isEmpty {
            throw SimulatorUIInputError.actionFailed(
                "typed the supported characters but these have no US-keyboard mapping: "
                    + "\(String(unsupported)). The hardware-keyboard path supports ASCII only.",
            )
        }
    }

    /// Presses a key. Hardware-button names (home/lock/siri/...) are routed to ``pressButton``;
    /// everything else is sent as a host keystroke (by key name or single character) to the focused
    /// Simulator window.
    public func pressKey(simulator: String, key: String) async throws {
        let normalized = key.lowercased()

        if Self.buttonAliases[normalized] != nil {
            try await pressButton(simulator: simulator, button: key)
            return
        }
        let device = try await resolveBootedDevice(simulator)
        try await focusWindow(deviceName: device.name)
        try await ensureHardwareKeyboardConnected()

        if let keyCode = Self.keyCodes[normalized] {
            postKeyCode(keyCode)
        } else if let character = key.first, key.count == 1, postCharacter(character) {
            // handled
        } else {
            throw SimulatorUIInputError.actionFailed("Unknown key '\(key)'")
        }
    }

    /// Presses a hardware button by driving the Simulator's *Device* menu.
    public func pressButton(simulator: String, button: String) async throws {
        let device = try await resolveBootedDevice(simulator)
        let normalized = button.lowercased()
        guard let menuItem = Self.buttonAliases[normalized] else {
            throw SimulatorUIInputError.unsupportedButton(button)
        }
        try await focusWindow(deviceName: device.name)
        try await clickDeviceMenuItem(menuItem)
    }

    // MARK: - Geometry

    /// The located screen geometry for a device: the global-coordinate rectangle of the device
    /// screen inside its Simulator window, plus the device pixel size used to normalize
    /// coordinates.
    private struct ScreenGeometry {
        let deviceName: String
        /// Device-screen rectangle in global display points (top-left origin), as used by
        /// `CGEvent`.
        let rect: CGRect
        /// Device screen size in pixels (the space tap/swipe coordinates are expressed in).
        let pixelSize: CGSize

        func mapFraction(fx: Double, fy: Double) -> CGPoint {
            .init(
                x: rect.minX + CGFloat(max(0, min(1, fx))) * rect.width,
                y: rect.minY + CGFloat(max(0, min(1, fy))) * rect.height,
            )
        }

        func map(x: Double, y: Double) -> CGPoint {
            mapFraction(fx: x / Double(pixelSize.width), fy: y / Double(pixelSize.height))
        }
    }

    private func geometry(for simulator: String) async throws -> ScreenGeometry {
        let device = try await resolveBootedDevice(simulator)
        var pixelSize = try await deviceScreenPixelSize(udid: device.udid)
        let window = try locateWindow(deviceName: device.name)
        var rect = try await detectScreenRect(window: window)

        // Validate the detected rectangle against the device aspect ratio. A mismatch usually means
        // the cache is stale (rotation) or detection failed — refresh the pixel size once.
        if !aspectMatches(rect: rect, pixel: pixelSize) {
            pixelSizeCache[device.udid] = nil
            pixelSize = try await deviceScreenPixelSize(udid: device.udid)
            // Re-locate in case the window moved/rotated between captures.
            let window2 = try locateWindow(deviceName: device.name)
            rect = try await detectScreenRect(window: window2)
            guard aspectMatches(rect: rect, pixel: pixelSize) else {
                throw SimulatorUIInputError.screenNotDetected(
                    "detected aspect \(format(rect.width / rect.height)) "
                        + "≠ device aspect \(format(pixelSize.width / pixelSize.height))",
                )
            }
        }

        return .init(deviceName: device.name, rect: rect, pixelSize: pixelSize)
    }

    private func aspectMatches(rect: CGRect, pixel: CGSize) -> Bool {
        guard rect.height > 0, pixel.height > 0 else { return false }
        let a = rect.width / rect.height
        let b = pixel.width / pixel.height
        return abs(a - b) / b < 0.06
    }

    private func format(_ value: CGFloat) -> String { .init(format: "%.3f", value) }

    // MARK: - Device resolution

    private struct BootedDevice {
        let udid: String
        let name: String
    }

    private func resolveBootedDevice(_ simulator: String) async throws -> BootedDevice {
        let devices: [SimulatorDevice]

        do {
            devices = try await simctlRunner.listDevices()
        } catch {
            throw SimulatorUIInputError.actionFailed("Failed to list simulators: \(error)")
        }
        guard let device = devices.first(where: { $0.udid == simulator || $0.name == simulator })
        else { throw SimulatorUIInputError.notBooted(simulator) }
        guard device.state == "Booted" else { throw SimulatorUIInputError.notBooted(device.name) }
        return .init(udid: device.udid, name: device.name)
    }

    /// Returns the device screen size in pixels, taking a screenshot the first time per UDID.
    private func deviceScreenPixelSize(udid: String) async throws -> CGSize {
        if let cached = pixelSizeCache[udid] { return cached }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("xc-mcp-simsize-\(udid).png").path
        let result = try? await simctlRunner.screenshot(udid: udid, outputPath: path)
        guard result?.succeeded == true,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double
        else {
            throw SimulatorUIInputError.actionFailed(
                "Could not read device screen size for '\(udid)' (screenshot failed).",
            )
        }
        try? FileManager.default.removeItem(atPath: path)
        let size = CGSize(width: w, height: h)
        pixelSizeCache[udid] = size
        return size
    }

    // MARK: - Window location

    private struct SimWindow {
        let id: CGWindowID
        let bounds: CGRect
    }

    private func locateWindow(deviceName: String) throws -> SimWindow {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID,
        ) as? [[String: Any]] else { throw SimulatorUIInputError.windowNotFound(deviceName) }

        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Simulator",
                  let title = info[kCGWindowName as String] as? String,
                  !title.isEmpty,
                  title == deviceName || title.hasPrefix("\(deviceName) "),
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"],
                  let y = b["Y"],
                  let w = b["Width"],
                  let h = b["Height"] else { continue }
            return SimWindow(id: wid, bounds: CGRect(x: x, y: y, width: w, height: h))
        }
        throw SimulatorUIInputError.windowNotFound(deviceName)
    }

    /// Captures the Simulator window and finds the device-screen rectangle inside it, converting
    /// the detected image-pixel rectangle to global display points. The window contains a title bar
    /// and (by default) a device bezel; ``ScreenRectDetector`` locates the screen within it.
    private func detectScreenRect(window: SimWindow) async throws -> CGRect {
        let capturePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("xc-mcp-siminput-\(window.id).png").path
        defer { try? FileManager.default.removeItem(atPath: capturePath) }

        do {
            let capture = try await ProcessResult.run(
                "/usr/sbin/screencapture",
                arguments: ["-o", "-x", "-l", "\(window.id)", capturePath],
                timeout: .seconds(15),
            )
            guard capture.succeeded else {
                throw SimulatorUIInputError.screenNotDetected(
                    "screencapture failed (exit \(capture.exitCode)): \(capture.errorOutput)",
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SimulatorUIInputError {
            throw error
        } catch {
            throw SimulatorUIInputError.screenNotDetected("screencapture failed: \(error)")
        }

        guard let image = NSImage(contentsOfFile: capturePath),
              let rep = image.representations.first as? NSBitmapImageRep
        else { throw SimulatorUIInputError.screenNotDetected("window capture unreadable") }

        let detector = ScreenRectDetector(rep: rep)
        guard let rectPx = detector.detect() else {
            throw SimulatorUIInputError.screenNotDetected("no screen region found in window")
        }

        // Convert image pixels → window points → global points.
        let scale = CGFloat(rep.pixelsWide) / window.bounds.width
        guard scale > 0 else { throw SimulatorUIInputError.screenNotDetected("bad capture scale") }
        return .init(
            x: window.bounds.minX + rectPx.minX / scale,
            y: window.bounds.minY + rectPx.minY / scale,
            width: rectPx.width / scale,
            height: rectPx.height / scale,
        )
    }

    // MARK: - Event posting

    private func postMouse(_ type: CGEventType, _ point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: point, mouseButton: .left,
        )?.post(tap: .cghidEventTap)
    }

    private func drag(from start: CGPoint, to end: CGPoint, duration: Double) async throws {
        postMouse(.mouseMoved, start)
        usleep(40_000)
        postMouse(.leftMouseDown, start)
        let steps = max(10, Int(duration * 60))
        let stepDelay = UInt32(max(1, duration / Double(steps) * 1_000_000))

        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * t,
                y: start.y + (end.y - start.y) * t,
            )
            postMouse(.leftMouseDragged, point)
            usleep(stepDelay)
        }
        postMouse(.leftMouseUp, end)
    }

    private func postKeyCode(_ keyCode: CGKeyCode, shift: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        if shift {
            down?.flags = .maskShift
            up?.flags = .maskShift
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Posts a single character as a hardware-keyboard keystroke. The Simulator interprets HID
    /// keycodes (not Unicode), so each character maps to a US-layout keycode plus an optional
    /// shift. Returns `false` for characters with no US-keyboard mapping.
    private func postCharacter(_ character: Character) -> Bool {
        if let keyCode = Self.unshiftedKeys[character] {
            postKeyCode(keyCode, shift: false)
            return true
        }
        if let keyCode = Self.shiftedKeys[character] {
            postKeyCode(keyCode, shift: true)
            return true
        }
        return false
    }

    // MARK: - AppleScript (focus + Device menu)

    private func focusWindow(deviceName: String) async throws {
        let safe = Self.appleScriptEscape(deviceName)
        let script = """
            tell application "Simulator" to activate
            tell application "System Events"
              tell process "Simulator"
                set ws to (every window whose (title is "\(safe)" or title starts with "\(safe) "))
                if (count of ws) is 0 then return "NO_WINDOW"
                perform action "AXRaise" of (item 1 of ws)
                return "OK"
              end tell
            end tell
            """
        let out = try await runOsa(script)
        if out == "NO_WINDOW" { throw SimulatorUIInputError.windowNotFound(deviceName) }
    }

    /// Ensures *I/O > Keyboard > Connect Hardware Keyboard* is checked, so host keystrokes are
    /// routed to the focused iOS field instead of the Simulator app. Idempotent — only toggles when
    /// the menu item is currently unchecked.
    private func ensureHardwareKeyboardConnected() async throws {
        let script = """
            tell application "System Events"
              tell process "Simulator"
                set mi to menu item "Connect Hardware Keyboard" of menu 1 ¬
                  of menu item "Keyboard" of menu 1 of menu bar item "I/O" of menu bar 1
                set mk to ""
                try
                  set mk to value of attribute "AXMenuItemMarkChar" of mi
                end try
                if mk is "" or mk is missing value then
                  click mi
                  return "ENABLED"
                end if
                return "ALREADY"
              end tell
            end tell
            """
        let result = try await runOsa(script)
        // Give the device a moment to attach the hardware keyboard before typing.
        if result == "ENABLED" { try await Task.sleep(for: .milliseconds(400)) }
    }

    private func clickDeviceMenuItem(_ item: String) async throws {
        let safe = Self.appleScriptEscape(item)
        let script = """
            tell application "System Events"
              tell process "Simulator"
                click menu item "\(safe)" of menu "Device" of menu bar 1
              end tell
            end tell
            """
        _ = try await runOsa(script)
    }

    @discardableResult
    private func runOsa(_ script: String) async throws -> String {
        let result: ProcessResult

        do {
            result = try await ProcessResult.run(
                "/usr/bin/osascript", arguments: ["-e", script],
                mergeStderr: false, timeout: .seconds(15),
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SimulatorUIInputError.actionFailed("osascript launch failed: \(error)")
        }
        guard result.succeeded else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SimulatorUIInputError.actionFailed(message.isEmpty ? "osascript failed" : message)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Tables

    /// Hardware-button / key aliases → Simulator *Device* menu item titles.
    static let buttonAliases: [String: String] = [
        "home": "Home",
        "lock": "Lock",
        "power": "Lock",
        "siri": "Siri",
        "shake": "Shake",
        "screenshot": "Trigger Screenshot",
        "rotate_left": "Rotate Left",
        "rotateleft": "Rotate Left",
        "rotate_right": "Rotate Right",
        "rotateright": "Rotate Right",
    ]

    /// Key name → virtual key code, mirroring ``InteractRunner`` for special keys.
    static let keyCodes: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
        "delete": 51, "backspace": 51, "forwarddelete": 117,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "pageup": 116, "pagedown": 121,
    ]

    /// Characters typed without shift on a US keyboard → virtual key code.
    static let unshiftedKeys: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        " ": 49, "\t": 48, "\n": 36, "\r": 36,
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39,
        ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    /// Characters typed with shift on a US keyboard → virtual key code (the shifted symbol's base).
    static let shiftedKeys: [Character: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "O": 31, "U": 32,
        "I": 34, "P": 35, "L": 37, "J": 38, "K": 40, "N": 45, "M": 46,
        "!": 18, "@": 19, "#": 20, "$": 21, "%": 23, "^": 22, "&": 26, "*": 28, "(": 25, ")": 29,
        "_": 27, "+": 24, "{": 33, "}": 30, "|": 42, ":": 41, "\"": 39,
        "<": 43, ">": 47, "?": 44, "~": 50,
    ]
}

/// Scans a captured Simulator-window bitmap for the device-screen rectangle (in image pixels).
///
/// The device screen is bounded by the near-black device bezel. Rather than trusting a single scan
/// line (which a dark band of content can split), this uses **projection profiles**: a column is
/// "screen" if only a small fraction of its pixels in a sampling band are bezel-black, and likewise
/// for rows. Bezel columns/rows are almost entirely black, so the longest run of screen columns
/// gives the left/right edges and the longest run of screen rows gives top/bottom — robust against
/// scattered dark content. The top/bottom pass samples **side bands** only, which dodges the
/// centered dynamic island and the rounded corners.
private struct ScreenRectDetector {
    let rep: NSBitmapImageRep

    func detect() -> CGRect? {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 16, height > 16 else { return nil }

        // Left/right edges: a column is "screen" if <40% of its pixels in the vertical middle band
        // (which skips the top island and bottom home indicator) are bezel-black.
        let rowLo = height * 35 / 100
        let rowHi = height * 65 / 100
        let (left, right) = longestRun(over: 0..<width) { x in
            blackFraction(rows: rowLo..<rowHi, at: x) < 0.4
        }
        guard left >= 0, right - left > width / 8 else { return nil }

        // Top/bottom edges: a row is "screen" if <40% of its pixels in two side bands (avoiding the
        // centered island and the rounded corners) are bezel-black.
        let span = right - left
        let bandA = (left + span * 10 / 100)..<(left + span * 28 / 100)
        let bandB = (right - span * 28 / 100)..<(right - span * 10 / 100)
        let (top, bottom) = longestRun(over: 0..<height) { y in
            blackFraction(columns: bandA, at: y) < 0.4 && blackFraction(columns: bandB, at: y) < 0.4
        }
        guard top >= 0, bottom - top > height / 8 else { return nil }

        return CGRect(
            x: CGFloat(left), y: CGFloat(top),
            width: CGFloat(right - left + 1), height: CGFloat(bottom - top + 1),
        )
    }

    /// Fraction of bezel-black pixels down column `x` across `rows` (sampled).
    private func blackFraction(rows: Range<Int>, at x: Int) -> Double {
        guard !rows.isEmpty else { return 1 }
        let step = max(1, rows.count / 60)
        var black = 0
        var total = 0
        var y = rows.lowerBound

        while y < rows.upperBound {
            if isBlack(x, y) { black += 1 }
            total += 1
            y += step
        }
        return total == 0 ? 1 : Double(black) / Double(total)
    }

    /// Fraction of bezel-black pixels across `columns` in row `y` (sampled).
    private func blackFraction(columns: Range<Int>, at y: Int) -> Double {
        guard !columns.isEmpty else { return 1 }
        let step = max(1, columns.count / 30)
        var black = 0
        var total = 0
        var x = columns.lowerBound

        while x < columns.upperBound {
            if isBlack(x, y) { black += 1 }
            total += 1
            x += step
        }
        return total == 0 ? 1 : Double(black) / Double(total)
    }

    /// Longest contiguous run of indices for which `predicate` holds.
    private func longestRun(over range: Range<Int>, _ predicate: (Int) -> Bool) -> (Int, Int) {
        var bestStart = -1
        var bestEnd = -2
        var runStart = -1

        for i in range {
            if predicate(i) {
                if runStart < 0 { runStart = i }

                if i - runStart > bestEnd - bestStart {
                    bestStart = runStart
                    bestEnd = i
                }
            } else {
                runStart = -1
            }
        }
        return (bestStart, bestEnd)
    }

    /// Whether a pixel is bezel-black (near-black across all channels).
    private func isBlack(_ x: Int, _ y: Int) -> Bool {
        guard let color = rep.colorAt(x: x, y: y) else { return true }
        return color.redComponent < 0.17 && color.greenComponent < 0.17
            && color.blueComponent < 0.17
    }
}
