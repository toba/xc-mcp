import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for physical iOS device operations.
///
/// This focused server provides tools for managing physical iOS devices, building and running apps,
/// and capturing logs.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.device`. Selecting a focused
/// server trims the tool surface a client pays for.
///
/// ## Tool Categories
///
/// - **Device management**: list connected devices
/// - **Build & run**: build, install, launch, stop apps
/// - **Logging**: capture device logs
/// - **Session**: manage default device and project settings
public struct DeviceMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    /// Creates a new device MCP server instance.
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
            name: "xc-device",
            version: "1.0.0",
            capabilities: .init(tools: .init()),
        )

        await installRegistryToolHandlers(
            on: server, as: .device, deps: ToolDeps(basePath: basePath))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
