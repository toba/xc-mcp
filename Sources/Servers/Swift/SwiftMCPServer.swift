import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for Swift Package Manager operations.
///
/// This focused server provides tools for building, testing, and running Swift packages using the
/// Swift CLI.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.swift`. Selecting a focused
/// server trims the tool surface a client pays for.
///
/// ## Tools
///
/// - Build: `swift_package_build`
/// - Test: `swift_package_test`
/// - Run: `swift_package_run`
/// - Clean: `swift_package_clean`
/// - List: `swift_package_list`
/// - Stop: `swift_package_stop`
public struct SwiftMCPServer: Sendable {
    private let basePath: String
    private let logger: Logger

    /// Creates a new swift MCP server instance.
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
        let server = Server(name: "xc-swift", version: "1.0.0", capabilities: .init(tools: .init()))

        await installRegistryToolHandlers(
            on: server, as: .swift, deps: ToolDeps(basePath: basePath))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
