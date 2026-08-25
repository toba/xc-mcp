import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for build orchestration, discovery, and utility tools.
///
/// This focused server provides tools for macOS builds, project discovery,
/// and general utilities like clean and scaffolding.
///
/// ## Token Efficiency
///
/// This server exposes the 59 tools `ToolRegistry` marks with `ServerSet.build`. Selecting a
/// focused server trims the tool surface a client pays for.
///
/// ## Tool Categories
///
/// - **macOS build**: build, test, run macOS applications
/// - **Discovery**: find projects, list schemes, query build settings
/// - **Utility**: clean, doctor, scaffold new projects
/// - **Session**: manage default project and build settings
public struct BuildMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new build MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - sandboxEnabled: Whether to enforce that paths stay within the base directory.
    ///     Defaults to `true`.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, sandboxEnabled: Bool = true, logger: Logger) {
        self.basePath = basePath
        self.sandboxEnabled = sandboxEnabled
        self.logger = logger
    }

    /// Starts the MCP server and begins processing requests.
    public func run() async throws {
        let server = Server(
            name: "xc-build",
            version: "1.0.0",
            capabilities: .init(tools: .init()),
        )

        await installRegistryToolHandlers(on: server, as: .build, deps: ToolDeps(basePath: basePath, sandboxEnabled: sandboxEnabled))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
