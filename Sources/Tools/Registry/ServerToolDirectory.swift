import XCMCPCore

/// Points an agent at the server that carries a tool the current server does not
///
/// The table derives from ``ToolRegistry``, so a tool added to a focused server is reachable from
/// this hint the moment its registration lands.
public enum ServerToolDirectory {
    /// Names the other servers that expose `toolName`, or `nil` when none does.
    public static func hint(for toolName: String, currentServer: ServerSet) -> String? {
        guard let servers = toolToServers[toolName] else { return nil }
        let others = servers.subtracting(currentServer).members.compactMap(\.executableName)
        guard !others.isEmpty else { return nil }
        let quoted = others.map { "'\($0)'" }
        let joined = quoted.count == 1
            ? quoted[0]
            : quoted.dropLast().joined(separator: ", ") + " and " + quoted[quoted.count - 1]
        return "This tool is available in the \(joined) server\(quoted.count == 1 ? "" : "s")."
    }

    /// The `methodNotFound` message for a name no server-hosted tool answers to.
    public static func unknownToolMessage(_ toolName: String, currentServer: ServerSet) -> String {
        let base = "Unknown tool: \(toolName)"
        guard let hint = hint(for: toolName, currentServer: currentServer) else { return base }
        return "\(base). \(hint)"
    }

    private static let toolToServers: [String: ServerSet] = {
        var map = [String: ServerSet](minimumCapacity: ToolRegistry.all.count)
        for registration in ToolRegistry.all { map[registration.name] = registration.servers }
        return map
    }()
}
