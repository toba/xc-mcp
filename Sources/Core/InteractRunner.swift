import AppKit
import ApplicationServices
import Foundation
import MCP

/// Represents a UI element discovered via the Accessibility API.
public struct InteractElement: Sendable {
    public let id: Int
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let value: String?
    public let identifier: String?
    public let roleDescription: String?
    public let position: CGPoint?
    public let size: CGSize?
    public let enabled: Bool
    public let focused: Bool
    public let actions: [String]
    public let depth: Int
    public let childCount: Int

    public func summary(indent: Bool = true) -> String {
        let prefix = indent ? String(repeating: "  ", count: depth) : ""
        var parts: [String] = []
        parts.append("[\(id)]")
        if let role { parts.append(role) }
        if let subrole { parts.append("(\(subrole))") }
        if let title, !title.isEmpty { parts.append("\"\(title)\"") }
        if let identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
        if let value, !value.isEmpty { parts.append("value=\(value)") }
        if !enabled { parts.append("disabled") }
        if focused { parts.append("focused") }
        if !actions.isEmpty { parts.append("actions=[\(actions.joined(separator: ","))]") }
        if childCount > 0 { parts.append("children=\(childCount)") }
        return prefix + parts.joined(separator: " ")
    }
}

/// Errors from Interact tools.
public enum InteractError: LocalizedError, Sendable, MCPErrorConvertible {
    case accessibilityNotTrusted
    case appNotFound(String)
    case elementNotFound(Int)
    case elementNotFoundByQuery(String)
    case actionFailed(String)
    case setValueFailed(String)
    case menuItemNotFound(String)
    case invalidKeyName(String)
    case noCache(pid_t)

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotTrusted:
            return
                "Accessibility permission not granted. Go to System Settings > Privacy & Security > Accessibility and add this app."
        case .appNotFound(let desc):
            return "Application not found: \(desc)"
        case .elementNotFound(let id):
            return
                "Element with ID \(id) not found in cache. Call interact_ui_tree first to refresh."
        case .elementNotFoundByQuery(let query):
            return "No element found matching: \(query)"
        case .actionFailed(let msg):
            return "Action failed: \(msg)"
        case .setValueFailed(let msg):
            return "Set value failed: \(msg)"
        case .menuItemNotFound(let path):
            return "Menu item not found: \(path)"
        case .invalidKeyName(let name):
            return
                "Invalid key name: \(name). Use names like 'return', 'tab', 'escape', 'space', 'a'-'z', '0'-'9', 'f1'-'f12', 'up', 'down', 'left', 'right', 'delete', 'home', 'end', 'pageup', 'pagedown'."
        case .noCache(let pid):
            return
                "No cached element tree for PID \(pid). Call interact_ui_tree first."
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
        case .accessibilityNotTrusted, .appNotFound, .elementNotFound,
            .elementNotFoundByQuery, .invalidKeyName, .noCache:
            return MCPError.invalidParams(errorDescription ?? "Unknown interact error")
        case .actionFailed, .setValueFailed, .menuItemNotFound:
            return MCPError.internalError(errorDescription ?? "Unknown interact error")
        }
    }
}

/// Wraps `AXUIElement` for safe passage across concurrency domains.
///
/// Access is serialized by `InteractSessionManager` actor.
public struct SendableAXUIElement: @unchecked Sendable {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }
}

/// Stateless runner providing Accessibility API operations.
public struct InteractRunner: Sendable {
    public init() {}

    // MARK: - Accessibility Check

    public func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    public func ensureAccessibility() throws {
        guard checkAccessibility() else {
            throw InteractError.accessibilityNotTrusted
        }
    }

    // MARK: - App Resolution

    public func resolveApp(
        pid: Int? = nil,
        bundleId: String? = nil,
        appName: String? = nil
    ) throws -> pid_t {
        if let pid {
            return pid_t(pid)
        }
        let apps = NSWorkspace.shared.runningApplications
        if let bundleId {
            guard let app = apps.first(where: { $0.bundleIdentifier == bundleId }) else {
                throw InteractError.appNotFound("bundle_id=\(bundleId)")
            }
            return app.processIdentifier
        }
        if let appName {
            guard
                let app = apps.first(where: {
                    $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
                })
            else {
                throw InteractError.appNotFound("app_name=\(appName)")
            }
            return app.processIdentifier
        }
        throw InteractError.appNotFound(
            "Provide at least one of: pid, bundle_id, or app_name")
    }

    /// Resolves the target PID from MCP tool arguments.
    public func resolveAppFromArguments(_ arguments: [String: Value]) throws -> pid_t {
        let pid = arguments.getInt("pid")
        let bundleId = arguments.getString("bundle_id")
        let appName = arguments.getString("app_name")
        return try resolveApp(pid: pid, bundleId: bundleId, appName: appName)
    }

    // MARK: - UI Tree Traversal

    /// Traverses the AX element tree and returns elements with their AXUIElement references.
    public func getUITree(
        pid: pid_t,
        maxDepth: Int = 3
    ) throws -> [(InteractElement, SendableAXUIElement)] {
        try ensureAccessibility()
        let appElement = AXUIElementCreateApplication(pid)
        var results: [(InteractElement, SendableAXUIElement)] = []
        var nextId = 0
        traverseElement(
            appElement, depth: 0, maxDepth: maxDepth, nextId: &nextId, results: &results)
        return results
    }

    private func traverseElement(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        nextId: inout Int,
        results: inout [(InteractElement, SendableAXUIElement)]
    ) {
        let info = getAttributes(from: element, id: nextId, depth: depth)
        let currentId = nextId
        nextId += 1

        // Get children before appending so we can set childCount
        var children: [AXUIElement] = []
        if depth < maxDepth {
            var childrenRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &childrenRef)
            if err == .success, let cfArray = childrenRef as? [AXUIElement] {
                children = cfArray
            }
        }

        let elementWithChildren = InteractElement(
            id: info.id,
            role: info.role,
            subrole: info.subrole,
            title: info.title,
            value: info.value,
            identifier: info.identifier,
            roleDescription: info.roleDescription,
            position: info.position,
            size: info.size,
            enabled: info.enabled,
            focused: info.focused,
            actions: info.actions,
            depth: info.depth,
            childCount: children.count
        )
        results.append((elementWithChildren, SendableAXUIElement(element)))

        for child in children {
            traverseElement(
                child, depth: depth + 1, maxDepth: maxDepth, nextId: &nextId, results: &results)
        }
    }

    // MARK: - Attribute Reading

    public func getAttributes(from element: AXUIElement, id: Int = 0, depth: Int = 0)
        -> InteractElement
    {
        let role = getStringAttribute(element, kAXRoleAttribute)
        let subrole = getStringAttribute(element, kAXSubroleAttribute)
        let title = getStringAttribute(element, kAXTitleAttribute)
        let rawValue = getAnyAttribute(element, kAXValueAttribute)
        let value: String? = rawValue.map { "\($0)" }
        let identifier = getStringAttribute(element, kAXIdentifierAttribute)
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute)
        let enabled = getBoolAttribute(element, kAXEnabledAttribute) ?? true
        let focused = getBoolAttribute(element, kAXFocusedAttribute) ?? false

        var position: CGPoint?
        var positionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
            == .success
        {
            var point = CGPoint.zero
            // swiftlint:disable:next force_cast
            if AXValueGetValue(positionRef as! AXValue, .cgPoint, &point) {
                position = point
            }
        }

        var size: CGSize?
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
            == .success
        {
            var sz = CGSize.zero
            // swiftlint:disable:next force_cast
            if AXValueGetValue(sizeRef as! AXValue, .cgSize, &sz) {
                size = sz
            }
        }

        var actions: [String] = []
        var actionsRef: CFArray?
        if AXUIElementCopyActionNames(element, &actionsRef) == .success,
            let actionNames = actionsRef as? [String]
        {
            actions = actionNames
        }

        var childCount = 0
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            == .success
        {
            if let arr = childrenRef as? [AXUIElement] {
                childCount = arr.count
            }
        }

        return InteractElement(
            id: id,
            role: role,
            subrole: subrole,
            title: title,
            value: value,
            identifier: identifier,
            roleDescription: roleDescription,
            position: position,
            size: size,
            enabled: enabled,
            focused: focused,
            actions: actions,
            depth: depth,
            childCount: childCount
        )
    }

    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard err == .success, let value = ref else { return nil }
        return value as? String
    }

    private func getAnyAttribute(_ element: AXUIElement, _ attribute: String) -> Any? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard err == .success, let value = ref else { return nil }
        return value
    }

    private func getBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard err == .success else { return nil }
        return (ref as? Bool)
    }

    // MARK: - Actions

    public func performAction(_ action: String, on element: AXUIElement) throws {
        let err = AXUIElementPerformAction(element, action as CFString)
        guard err == .success else {
            throw InteractError.actionFailed(
                "\(action) failed with error code \(err.rawValue)")
        }
    }

    // MARK: - Set Value

    public func setValue(_ value: String, on element: AXUIElement) throws {
        // First try to focus the element
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)

        let err = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, value as CFTypeRef)
        guard err == .success else {
            throw InteractError.setValueFailed(
                "Failed to set value with error code \(err.rawValue)")
        }
    }

    // MARK: - Menu Navigation

    public func navigateMenu(pid: pid_t, menuPath: [String]) throws {
        try ensureAccessibility()
        let appElement = AXUIElementCreateApplication(pid)

        // Get menu bar
        var menuBarRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            appElement, kAXMenuBarAttribute as CFString, &menuBarRef)
        guard err == .success, let menuBar = menuBarRef else {
            throw InteractError.menuItemNotFound("Cannot access menu bar")
        }
        // swiftlint:disable:next force_cast
        let menuBarElement = menuBar as! AXUIElement

        var currentElement: AXUIElement = menuBarElement
        for (index, itemName) in menuPath.enumerated() {
            guard let child = findChildByTitle(currentElement, title: itemName) else {
                let traversed = menuPath[0..<index].joined(separator: " > ")
                throw InteractError.menuItemNotFound(
                    "'\(itemName)' not found" + (traversed.isEmpty ? "" : " after \(traversed)"))
            }

            if index < menuPath.count - 1 {
                // Open submenu
                try performAction(kAXPressAction, on: child)
                // Small delay to let menu open
                Thread.sleep(forTimeInterval: 0.1)
                // Navigate into the opened submenu's children
                var submenuRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    child, kAXChildrenAttribute as CFString, &submenuRef) == .success,
                    let submenuChildren = submenuRef as? [AXUIElement],
                    let submenu = submenuChildren.first
                {
                    currentElement = submenu
                } else {
                    currentElement = child
                }
            } else {
                // Click final item
                try performAction(kAXPressAction, on: child)
            }
        }
    }

    private func findChildByTitle(_ element: AXUIElement, title: String) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else { return nil }

        for child in children {
            if let childTitle = getStringAttribute(child, kAXTitleAttribute),
                childTitle.localizedCaseInsensitiveCompare(title) == .orderedSame
            {
                return child
            }
        }
        return nil
    }

    // MARK: - Keyboard Events

    public func sendKeyEvent(keyName: String, modifiers: [String] = []) throws {
        guard let keyCode = Self.keyCodes[keyName.lowercased()] else {
            throw InteractError.invalidKeyName(keyName)
        }

        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            default: break
            }
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            throw InteractError.actionFailed("Failed to create key events")
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Element Search

    /// Searches the element tree for elements matching the given criteria.
    public func findElements(
        pid: pid_t,
        role: String? = nil,
        title: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        maxDepth: Int = 10
    ) throws -> [(InteractElement, SendableAXUIElement)] {
        let tree = try getUITree(pid: pid, maxDepth: maxDepth)
        return tree.filter { element, _ in
            if let role, element.role?.localizedCaseInsensitiveContains(role) != true {
                return false
            }
            if let title, element.title?.localizedCaseInsensitiveContains(title) != true {
                return false
            }
            if let identifier,
                element.identifier?.localizedCaseInsensitiveContains(identifier) != true
            {
                return false
            }
            if let value, element.value?.localizedCaseInsensitiveContains(value) != true {
                return false
            }
            return true
        }
    }

    // MARK: - Key Code Map

    static let keyCodes: [String: CGKeyCode] = [
        // Letters
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        // Numbers
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22,
        "7": 26, "8": 28, "9": 25,
        // Special
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53,
        "esc": 53, "delete": 51, "backspace": 51, "forwarddelete": 117,
        // Modifiers (for standalone press)
        "shift": 56, "command": 55, "cmd": 55, "option": 58, "alt": 58,
        "control": 59, "ctrl": 59,
        // Navigation
        "up": 126, "down": 125, "left": 123, "right": 124,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        // Function keys
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        // Punctuation
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39,
        ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    // MARK: - App Resolution Schema Properties

    /// Common schema properties for app identification, used across interact tools.
    public static var appResolutionSchemaProperties: [String: Value] {
        [
            "pid": .object([
                "type": .string("integer"),
                "description": .string("Process ID of the target application."),
            ]),
            "bundle_id": .object([
                "type": .string("string"),
                "description": .string(
                    "Bundle identifier of the target application (e.g., 'com.apple.finder')."),
            ]),
            "app_name": .object([
                "type": .string("string"),
                "description": .string(
                    "Name of the target application (e.g., 'Finder'). Case-insensitive substring match."
                ),
            ]),
        ]
    }
}
