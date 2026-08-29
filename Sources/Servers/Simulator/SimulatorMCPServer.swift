import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for iOS Simulator operations.
///
/// This focused server provides tools for managing iOS simulators, building and running apps, UI
/// automation, and log capture.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.simulator`. Selecting a
/// focused server trims the tool surface a client pays for.
///
/// ## Tool Categories
///
/// - **Simulator management**: list, boot, open, erase simulators
/// - **Build & run**: build, install, launch, stop apps
/// - **UI automation**: tap, swipe, type text, press keys, take screenshots
/// - **Logging**: capture simulator logs
/// - **Session**: manage default simulator and project settings
public struct SimulatorMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    /// Creates a new simulator MCP server instance.
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
        let server = Server(
            name: "xc-simulator",
            version: "1.0.0",
            capabilities: .init(tools: .init()),
        )

        await installRegistryToolHandlers(
            on: server, as: .simulator, deps: ToolDeps(basePath: basePath))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
