import MCP
import XCMCPCore

/// Every tool this package ships, declared once
///
/// A tool appears in exactly one ``ToolRegistration`` here. That record carries the MCP name, the
/// workflow the monolith gates it behind, the servers that expose it, its descriptor and its
/// runner. Every server, and ``ServerToolDirectory``, reads this table instead of restating the
/// tool in an enum, a descriptor array and a dispatch switch.
///
/// To add a tool, write one registration in the category file its workflow belongs to and list the
/// servers that should expose it. Nothing else needs an edit.
public enum ToolRegistry {
    /// Every registration, ordered by category.
    public static let all: [ToolRegistration] = [
        project1, project2, project3, simulator, device, macOS, debug, swift, utility, session,
        strings,
    ].flatMap { $0 }

    /// The registrations one server exposes.
    public static func registrations(for servers: ServerSet) -> [ToolRegistration] {
        all.filter { !$0.servers.isDisjoint(with: servers) }
    }
}
