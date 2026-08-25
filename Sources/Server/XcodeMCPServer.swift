import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// The main MCP server for Xcode development operations.
///
/// `XcodeMCPServer` exposes every tool ``ToolRegistry`` marks with `ServerSet.monolith` for Xcode
/// project manipulation, building, testing, and device management through the Model Context
/// Protocol (MCP).
///
/// ## Overview
///
/// The server provides tools organized into categories:
/// - **Project tools**: Create and modify Xcode projects (.xcodeproj files)
/// - **Simulator tools**: Build, install, and run apps on iOS simulators
/// - **Device tools**: Build, install, and run apps on physical devices
/// - **macOS tools**: Build and run macOS applications
/// - **Debug tools**: LLDB debugging operations
/// - **UI Automation tools**: Interact with simulator UI elements
/// - **Swift Package tools**: Build and test Swift packages
///
/// A client trims this surface with `manage_workflows`, which disables a whole ``Workflow`` at
/// once.
///
/// ## Usage
///
/// ```swift
/// let server = XcodeMCPServer(basePath: "/path/to/projects", logger: logger)
/// try await server.run()
/// ```
public struct XcodeMCPServer: Sendable {
    /// The base path for all file operations.
    private let basePath: String

    /// Logger instance for server diagnostics.
    private let logger: Logger

    /// Creates a new Xcode MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations. All paths are validated to be within
    ///     this directory for security.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, logger: Logger) {
        self.basePath = basePath
        self.logger = logger
    }

    /// Starts the MCP server and begins processing requests.
    ///
    /// This method initializes all tool handlers and starts the server using stdio transport. It
    /// blocks until the server completes or encounters an error.
    ///
    /// - Throws: An error if the server fails to start or encounters a fatal error.
    public func run() async throws {
        let server = Server(
            name: "xcode-mcp-server",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: true)),
        )

        let deps = ToolDeps(basePath: basePath) {
            try await server.notify(
                Message<ToolListChangedNotification>(
                    method: ToolListChangedNotification.name, params: Empty(),
                ),
            )
        }
        await installRegistryToolHandlers(
            on: server, as: .monolith, deps: deps, gateByWorkflow: true,
        )

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
