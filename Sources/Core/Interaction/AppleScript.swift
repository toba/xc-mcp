import Foundation

/// Helpers for building AppleScript sent to `osascript` from the interaction tools.
enum AppleScript {
    /// Escapes a string for safe interpolation inside an AppleScript string literal.
    ///
    /// Escapes the backslash and double-quote (which would otherwise terminate the literal) plus
    /// the newline/carriage-return/tab control characters, so a window or menu title containing any
    /// of them can't break out of the surrounding `"..."`.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    /// Builds a script that activates the Simulator, raises the window whose title matches
    /// `deviceName` (exact, or `"<name> …"` for the `"<name> – <OS>"` form), and returns `"OK"`.
    /// Returns `"NO_WINDOW"` when no window matches.
    static func raiseSimulatorWindow(named deviceName: String) -> String {
        let safe = escape(deviceName)
        return """
            tell application "Simulator" to activate
            tell application "System Events"
              tell process "Simulator"
                set frontmost to true
                set ws to (every window whose (title is "\(safe)" or title starts with "\(safe) "))
                if (count of ws) is 0 then return "NO_WINDOW"
                perform action "AXRaise" of (item 1 of ws)
                return "OK"
              end tell
            end tell
            """
    }
}
