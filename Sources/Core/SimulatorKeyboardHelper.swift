import MCP
import Foundation

/// Sends keyboard shortcuts to the macOS Simulator app to toggle its keyboard state.
///
/// The Simulator menu items "I/O > Keyboard > Toggle Software Keyboard" (`Cmd+K`) and
/// "Connect Hardware Keyboard" (`Cmd+Shift+K`) are not exposed by `simctl`. This helper
/// drives them via AppleScript: it focuses the Simulator window matching the booted
/// device and sends the corresponding keystroke.
public enum SimulatorKeyboardHelper {
    /// Which keyboard menu item to toggle.
    public enum Shortcut: Sendable {
        /// `I/O > Keyboard > Toggle Software Keyboard` — `Cmd+K`.
        case softwareKeyboard
        /// `I/O > Keyboard > Connect Hardware Keyboard` — `Cmd+Shift+K`.
        case connectHardwareKeyboard

        var modifiers: String {
            switch self {
                case .softwareKeyboard: "{command down}"
                case .connectHardwareKeyboard: "{command down, shift down}"
            }
        }
    }

    /// Resolves the booted simulator's name from its UDID, focuses its Simulator window,
    /// and sends the keystroke for the requested shortcut.
    ///
    /// - Parameters:
    ///   - udid: UDID of a booted simulator.
    ///   - shortcut: Which keyboard menu item to toggle.
    ///   - simctlRunner: Runner used to look up device state.
    /// - Throws: ``MCPError/invalidParams(_:)`` if the simulator isn't booted, or
    ///   ``MCPError/internalError(_:)`` if AppleScript fails.
    public static func sendShortcut(
        udid: String,
        shortcut: Shortcut,
        simctlRunner: SimctlRunner = SimctlRunner(),
    ) async throws {
        let device = try await resolveBootedDevice(udid: udid, simctlRunner: simctlRunner)
        try await focusSimulatorWindow(deviceName: device.name)
        try await sendKeystroke(shortcut: shortcut)
    }

    private static func resolveBootedDevice(
        udid: String,
        simctlRunner: SimctlRunner,
    ) async throws -> SimulatorDevice {
        let devices: [SimulatorDevice]
        do {
            devices = try await simctlRunner.listDevices()
        } catch {
            throw MCPError.internalError("Failed to list simulators: \(error)")
        }
        guard let device = devices.first(where: { $0.udid == udid }) else {
            throw MCPError.invalidParams("No simulator found with UDID '\(udid)'")
        }
        guard device.state == "Booted" else {
            throw MCPError.invalidParams(
                "Simulator '\(device.name)' is \(device.state). Boot it first with boot_sim.",
            )
        }
        return device
    }

    private static func focusSimulatorWindow(deviceName: String) async throws {
        let safeName = appleScriptEscape(deviceName)
        let script = """
        tell application "System Events"
          tell process "Simulator"
            set frontmost to true
            set matchingWindows to (every window whose (title is "\(safeName)" or title starts with "\(safeName) –" or title starts with "\(safeName) -"))
            if (count of matchingWindows) is 0 then
              return "NO_WINDOW"
            end if
            perform action "AXRaise" of (item 1 of matchingWindows)
            return "OK"
          end tell
        end tell
        """
        let result = try await ProcessResult.run(
            "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: .seconds(5),
        )
        if !result.succeeded {
            throw MCPError.internalError(
                "Failed to focus Simulator window: \(result.stderr.isEmpty ? result.stdout : result.stderr)",
            )
        }
        if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "NO_WINDOW" {
            throw MCPError.internalError(
                "No Simulator window matched '\(deviceName)'. Open the Simulator app and try again.",
            )
        }
    }

    private static func sendKeystroke(shortcut: Shortcut) async throws {
        let script = """
        tell application "System Events"
          tell process "Simulator"
            keystroke "k" using \(shortcut.modifiers)
          end tell
        end tell
        """
        let result = try await ProcessResult.run(
            "/usr/bin/osascript",
            arguments: ["-e", script],
            timeout: .seconds(5),
        )
        if !result.succeeded {
            throw MCPError.internalError(
                "Failed to send keystroke: \(result.stderr.isEmpty ? result.stdout : result.stderr)",
            )
        }
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
