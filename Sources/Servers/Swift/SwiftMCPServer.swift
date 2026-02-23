import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// All available tool names exposed by the xc-swift MCP server.
public enum SwiftToolName: String, CaseIterable, Sendable {
    case swiftPackageBuild = "swift_package_build"
    case swiftPackageTest = "swift_package_test"
    case swiftPackageRun = "swift_package_run"
    case swiftPackageClean = "swift_package_clean"
    case swiftPackageList = "swift_package_list"
    case swiftPackageStop = "swift_package_stop"
    case swiftFormat = "swift_format"
    case swiftLint = "swift_lint"
    case swiftDiagnostics = "swift_diagnostics"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
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
            capabilities: .init(tools: .init()),
        )

        // Create utilities
        let swiftRunner = SwiftRunner()
        let sessionManager = SessionManager()

        // Create Swift package tools
        let swiftPackageBuildTool = SwiftPackageBuildTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageTestTool = SwiftPackageTestTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageRunTool = SwiftPackageRunTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageCleanTool = SwiftPackageCleanTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageListTool = SwiftPackageListTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )
        let swiftPackageStopTool = SwiftPackageStopTool(sessionManager: sessionManager)
        let swiftFormatTool = SwiftFormatTool(sessionManager: sessionManager)
        let swiftLintTool = SwiftLintTool(sessionManager: sessionManager)
        let swiftDiagnosticsTool = SwiftDiagnosticsTool(
            swiftRunner: swiftRunner, sessionManager: sessionManager,
        )

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                swiftPackageBuildTool.tool(),
                swiftPackageTestTool.tool(),
                swiftPackageRunTool.tool(),
                swiftPackageCleanTool.tool(),
                swiftPackageListTool.tool(),
                swiftPackageStopTool.tool(),
                swiftFormatTool.tool(),
                swiftLintTool.tool(),
                swiftDiagnosticsTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = SwiftToolName(rawValue: params.name) else {
                let hint = ServerToolDirectory.hint(for: params.name, currentServer: "xc-swift")
                let message =
                    hint.map { "Unknown tool: \(params.name). \($0)" }
                        ?? "Unknown tool: \(params.name)"
                throw MCPError.methodNotFound(message)
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
                case .swiftFormat:
                    return try await swiftFormatTool.execute(arguments: arguments)
                case .swiftLint:
                    return try await swiftLintTool.execute(arguments: arguments)
                case .swiftDiagnostics:
                    return try await swiftDiagnosticsTool.execute(arguments: arguments)
                // Session tools
                case .setSessionDefaults:
                    return try await setSessionDefaultsTool.execute(arguments: arguments)
                case .showSessionDefaults:
                    return try await showSessionDefaultsTool.execute(arguments: arguments)
                case .clearSessionDefaults:
                    return try await clearSessionDefaultsTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
