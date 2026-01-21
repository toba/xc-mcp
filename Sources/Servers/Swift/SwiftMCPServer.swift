import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-swift MCP server.
public enum SwiftToolName: String, CaseIterable, Sendable {
    case swiftPackageBuild = "swift_package_build"
    case swiftPackageTest = "swift_package_test"
    case swiftPackageRun = "swift_package_run"
    case swiftPackageClean = "swift_package_clean"
    case swiftPackageList = "swift_package_list"
    case swiftPackageStop = "swift_package_stop"
}

/// MCP server for Swift Package Manager operations.
///
/// This focused server provides tools for building, testing, and running
/// Swift packages using the Swift CLI.
///
/// ## Token Efficiency
///
/// This server exposes 6 tools with approximately 1.5K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// Swift package capabilities.
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

    /// Creates a new Swift MCP server instance.
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
            name: "xc-swift",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create utilities
        let swiftRunner = SwiftRunner()
        let sessionManager = SessionManager()

        // Create Swift package tools
        let swiftPackageBuildTool = SwiftPackageBuildTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageTestTool = SwiftPackageTestTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageRunTool = SwiftPackageRunTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageCleanTool = SwiftPackageCleanTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageListTool = SwiftPackageListTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager)
        let swiftPackageStopTool = SwiftPackageStopTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                swiftPackageBuildTool.tool(),
                swiftPackageTestTool.tool(),
                swiftPackageRunTool.tool(),
                swiftPackageCleanTool.tool(),
                swiftPackageListTool.tool(),
                swiftPackageStopTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = SwiftToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            case .swiftPackageBuild:
                return try await swiftPackageBuildTool.execute(arguments: arguments)
            case .swiftPackageTest:
                return try await swiftPackageTestTool.execute(arguments: arguments)
            case .swiftPackageRun:
                return try await swiftPackageRunTool.execute(arguments: arguments)
            case .swiftPackageClean:
                return try await swiftPackageCleanTool.execute(arguments: arguments)
            case .swiftPackageList:
                return try await swiftPackageListTool.execute(arguments: arguments)
            case .swiftPackageStop:
                return try await swiftPackageStopTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
