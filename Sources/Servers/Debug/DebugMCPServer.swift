import Foundation
import Logging
import MCP
import XCMCPCore
import XCMCPTools

/// All available tool names exposed by the xc-debug MCP server.
public enum DebugToolName: String, CaseIterable, Sendable {
    case debugAttachSim = "debug_attach_sim"
    case debugDetach = "debug_detach"
    case debugBreakpointAdd = "debug_breakpoint_add"
    case debugBreakpointRemove = "debug_breakpoint_remove"
    case debugContinue = "debug_continue"
    case debugStack = "debug_stack"
    case debugVariables = "debug_variables"
    case debugLLDBCommand = "debug_lldb_command"
}

/// MCP server for LLDB debugging operations.
///
/// This focused server provides tools for debugging iOS apps using LLDB.
/// It manages persistent debug sessions and supports attaching to processes,
/// setting breakpoints, and inspecting program state.
///
/// ## Token Efficiency
///
/// This server exposes 8 tools with approximately 2K token overhead, compared to
/// ~50K for the full monolithic xc-mcp server. Use this server when you only need
/// debugging capabilities.
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
        let server = Server(
            name: "xc-debug",
            version: "1.0.0",
            capabilities: .init(tools: .init())
        )

        // Create utilities
        let lldbRunner = LLDBRunner()
        let simctlRunner = SimctlRunner()
        let sessionManager = SessionManager()

        // Create debug tools
        let debugAttachSimTool = DebugAttachSimTool(
            lldbRunner: lldbRunner, simctlRunner: simctlRunner, sessionManager: sessionManager)
        let debugDetachTool = DebugDetachTool(lldbRunner: lldbRunner)
        let debugBreakpointAddTool = DebugBreakpointAddTool(lldbRunner: lldbRunner)
        let debugBreakpointRemoveTool = DebugBreakpointRemoveTool(lldbRunner: lldbRunner)
        let debugContinueTool = DebugContinueTool(lldbRunner: lldbRunner)
        let debugStackTool = DebugStackTool(lldbRunner: lldbRunner)
        let debugVariablesTool = DebugVariablesTool(lldbRunner: lldbRunner)
        let debugLLDBCommandTool = DebugLLDBCommandTool(lldbRunner: lldbRunner)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                debugAttachSimTool.tool(),
                debugDetachTool.tool(),
                debugBreakpointAddTool.tool(),
                debugBreakpointRemoveTool.tool(),
                debugContinueTool.tool(),
                debugStackTool.tool(),
                debugVariablesTool.tool(),
                debugLLDBCommandTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = DebugToolName(rawValue: params.name) else {
                throw MCPError.methodNotFound("Unknown tool: \(params.name)")
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
            case .debugAttachSim:
                return try await debugAttachSimTool.execute(arguments: arguments)
            case .debugDetach:
                return try await debugDetachTool.execute(arguments: arguments)
            case .debugBreakpointAdd:
                return try await debugBreakpointAddTool.execute(arguments: arguments)
            case .debugBreakpointRemove:
                return try await debugBreakpointRemoveTool.execute(arguments: arguments)
            case .debugContinue:
                return try await debugContinueTool.execute(arguments: arguments)
            case .debugStack:
                return try await debugStackTool.execute(arguments: arguments)
            case .debugVariables:
                return try await debugVariablesTool.execute(arguments: arguments)
            case .debugLLDBCommand:
                return try await debugLLDBCommandTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
