import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for LLDB debugging operations.
///
/// This focused server provides tools for debugging iOS apps using LLDB. It manages persistent
/// debug sessions and supports attaching to processes, setting breakpoints, and inspecting program
/// state.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.debug`. Selecting a focused
/// server trims the tool surface a client pays for.
///
/// ## Tools
///
/// - Session management: `debug_attach_sim`, `debug_detach`
/// - Breakpoints: `debug_breakpoint_add`, `debug_breakpoint_remove`
/// - Execution: `debug_continue`
/// - Inspection: `debug_stack`, `debug_variables`
/// - Commands: `debug_lldb_command`
public struct DebugMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    /// Creates a new debug MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    /// Starts the MCP server and begins processing requests.
    public func run() async throws {
        let server = Server(name: "xc-debug", version: "1.0.0", capabilities: .init(tools: .init()))

        await installRegistryToolHandlers(
            on: server, as: .debug, deps: ToolDeps(basePath: basePath))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
