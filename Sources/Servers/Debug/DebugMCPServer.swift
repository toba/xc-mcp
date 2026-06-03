import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// All available tool names exposed by the xc-debug MCP server.
public enum DebugToolName: String, CaseIterable, Sendable {
    case buildDebugMacOS = "build_debug_macos"
    case debugAttachSim = "debug_attach_sim"
    case debugDetach = "debug_detach"
    case debugBreakpointAdd = "debug_breakpoint_add"
    case debugBreakpointRemove = "debug_breakpoint_remove"
    case debugContinue = "debug_continue"
    case debugStack = "debug_stack"
    case debugCaptureBacktrace = "debug_capture_backtrace"
    case debugVariables = "debug_variables"
    case debugLLDBCommand = "debug_lldb_command"
    case debugEvaluate = "debug_evaluate"
    case debugThreads = "debug_threads"
    case debugWatchpoint = "debug_watchpoint"
    case debugStep = "debug_step"
    case debugMemory = "debug_memory"
    case debugSymbolLookup = "debug_symbol_lookup"
    case debugViewHierarchy = "debug_view_hierarchy"
    case debugViewBorders = "debug_view_borders"
    case debugProcessStatus = "debug_process_status"

    // Memory diagnostic tools
    case memoryLeaks = "memory_leaks"
    case memoryHeap = "memory_heap"
    case memoryVmmap = "memory_vmmap"
    case memoryStringdups = "memory_stringdups"
    case memoryMallocHistory = "memory_malloc_history"

    // Crash symbolication
    case symbolicateAddress = "symbolicate_address"

    /// macOS tools
    case screenshotMacWindow = "screenshot_mac_window"

    // Interact tools (macOS Accessibility API)
    case interactUITree = "interact_ui_tree"
    case interactClick = "interact_click"
    case interactSetValue = "interact_set_value"
    case interactGetValue = "interact_get_value"
    case interactMenu = "interact_menu"
    case interactFocus = "interact_focus"
    case interactKey = "interact_key"
    case interactFind = "interact_find"

    // Session tools
    case setSessionDefaults = "set_session_defaults"
    case showSessionDefaults = "show_session_defaults"
    case clearSessionDefaults = "clear_session_defaults"
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
            capabilities: .init(tools: .init()),
        )

        // Create utilities
        let lldbRunner = LLDBRunner()
        let simctlRunner = SimctlRunner()
        let sessionManager = SessionManager()

        // Create debug tools
        let xcodebuildRunner = XcodebuildRunner()
        let buildDebugMacOSTool = BuildDebugMacOSTool(
            xcodebuildRunner: xcodebuildRunner, lldbRunner: lldbRunner,
            sessionManager: sessionManager,
        )
        let debugAttachSimTool = DebugAttachSimTool(
            lldbRunner: lldbRunner, simctlRunner: simctlRunner, sessionManager: sessionManager,
        )
        let debugDetachTool = DebugDetachTool(lldbRunner: lldbRunner)
        let debugBreakpointAddTool = DebugBreakpointAddTool(lldbRunner: lldbRunner)
        let debugBreakpointRemoveTool = DebugBreakpointRemoveTool(lldbRunner: lldbRunner)
        let debugContinueTool = DebugContinueTool(lldbRunner: lldbRunner)
        let debugStackTool = DebugStackTool(lldbRunner: lldbRunner)
        let debugCaptureBacktraceTool = DebugCaptureBacktraceTool(lldbRunner: lldbRunner)
        let debugVariablesTool = DebugVariablesTool(lldbRunner: lldbRunner)
        let debugLLDBCommandTool = DebugLLDBCommandTool(lldbRunner: lldbRunner)
        let debugEvaluateTool = DebugEvaluateTool(lldbRunner: lldbRunner)
        let debugThreadsTool = DebugThreadsTool(lldbRunner: lldbRunner)
        let debugWatchpointTool = DebugWatchpointTool(lldbRunner: lldbRunner)
        let debugStepTool = DebugStepTool(lldbRunner: lldbRunner)
        let debugMemoryTool = DebugMemoryTool(lldbRunner: lldbRunner)
        let debugSymbolLookupTool = DebugSymbolLookupTool(lldbRunner: lldbRunner)
        let debugViewHierarchyTool = DebugViewHierarchyTool(lldbRunner: lldbRunner)
        let debugViewBordersTool = DebugViewBordersTool(lldbRunner: lldbRunner)
        let debugProcessStatusTool = DebugProcessStatusTool(lldbRunner: lldbRunner)

        // Create memory diagnostic tools
        let memoryLeaksTool = MemoryLeaksTool()
        let memoryHeapTool = MemoryHeapTool()
        let memoryVmmapTool = MemoryVmmapTool()
        let memoryStringDupsTool = MemoryStringDupsTool()
        let memoryMallocHistoryTool = MemoryMallocHistoryTool()

        // Create crash symbolication tool
        let symbolicateAddressTool = SymbolicateAddressTool()

        // Create macOS tools
        let screenshotMacWindowTool = ScreenshotMacWindowTool()

        // Create interact tools (macOS Accessibility API)
        let interactRunner = InteractRunner()
        let interactUITreeTool = InteractUITreeTool(interactRunner: interactRunner)
        let interactClickTool = InteractClickTool(interactRunner: interactRunner)
        let interactSetValueTool = InteractSetValueTool(interactRunner: interactRunner)
        let interactGetValueTool = InteractGetValueTool(interactRunner: interactRunner)
        let interactMenuTool = InteractMenuTool(interactRunner: interactRunner)
        let interactFocusTool = InteractFocusTool(interactRunner: interactRunner)
        let interactKeyTool = InteractKeyTool(interactRunner: interactRunner)
        let interactFindTool = InteractFindTool(interactRunner: interactRunner)

        // Create session tools
        let setSessionDefaultsTool = SetSessionDefaultsTool(sessionManager: sessionManager)
        let showSessionDefaultsTool = ShowSessionDefaultsTool(sessionManager: sessionManager)
        let clearSessionDefaultsTool = ClearSessionDefaultsTool(sessionManager: sessionManager)

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
                buildDebugMacOSTool.tool(),
                debugAttachSimTool.tool(),
                debugDetachTool.tool(),
                debugBreakpointAddTool.tool(),
                debugBreakpointRemoveTool.tool(),
                debugContinueTool.tool(),
                debugStackTool.tool(),
                debugCaptureBacktraceTool.tool(),
                debugVariablesTool.tool(),
                debugLLDBCommandTool.tool(),
                debugEvaluateTool.tool(),
                debugThreadsTool.tool(),
                debugWatchpointTool.tool(),
                debugStepTool.tool(),
                debugMemoryTool.tool(),
                debugSymbolLookupTool.tool(),
                debugViewHierarchyTool.tool(),
                debugViewBordersTool.tool(),
                debugProcessStatusTool.tool(),
                // Memory diagnostic tools
                memoryLeaksTool.tool(),
                memoryHeapTool.tool(),
                memoryVmmapTool.tool(),
                memoryStringDupsTool.tool(),
                memoryMallocHistoryTool.tool(),
                // Crash symbolication
                symbolicateAddressTool.tool(),
                // macOS tools
                screenshotMacWindowTool.tool(),
                // Interact tools (macOS Accessibility API)
                interactUITreeTool.tool(),
                interactClickTool.tool(),
                interactSetValueTool.tool(),
                interactGetValueTool.tool(),
                interactMenuTool.tool(),
                interactFocusTool.tool(),
                interactKeyTool.tool(),
                interactFindTool.tool(),
                // Session tools
                setSessionDefaultsTool.tool(),
                showSessionDefaultsTool.tool(),
                clearSessionDefaultsTool.tool(),
            ])
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            guard let toolName = DebugToolName(rawValue: params.name) else {
                let hint = ServerToolDirectory.hint(for: params.name, currentServer: "xc-debug")
                let message =
                    hint.map { "Unknown tool: \(params.name). \($0)" }
                        ?? "Unknown tool: \(params.name)"
                throw MCPError.methodNotFound(message)
            }

            let arguments = params.arguments ?? [:]

            switch toolName {
                case .buildDebugMacOS:
                    if let token = params._meta?.progressToken {
                        let reporter = ProgressReporter(token: token) { msg in
                            try await server.notify(msg)
                        }
                        return try await reporter.stream {
                            try await buildDebugMacOSTool.execute(
                                arguments: arguments, onProgress: reporter.onProgress,
                            )
                        }
                    }
                    return try await buildDebugMacOSTool.execute(arguments: arguments)
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
                case .debugCaptureBacktrace:
                    return try await debugCaptureBacktraceTool.execute(arguments: arguments)
                case .debugVariables:
                    return try await debugVariablesTool.execute(arguments: arguments)
                case .debugLLDBCommand:
                    return try await debugLLDBCommandTool.execute(arguments: arguments)
                case .debugEvaluate:
                    if let token = params._meta?.progressToken {
                        return try await debugEvaluateTool.executeWithProgress(
                            arguments: arguments,
                            progressToken: token,
                        ) { msg in try await server.notify(msg) }
                    }
                    return try await debugEvaluateTool.execute(arguments: arguments)
                case .debugThreads:
                    return try await debugThreadsTool.execute(arguments: arguments)
                case .debugWatchpoint:
                    return try await debugWatchpointTool.execute(arguments: arguments)
                case .debugStep:
                    return try await debugStepTool.execute(arguments: arguments)
                case .debugMemory:
                    return try await debugMemoryTool.execute(arguments: arguments)
                case .debugSymbolLookup:
                    return try await debugSymbolLookupTool.execute(arguments: arguments)
                case .debugViewHierarchy:
                    return try await debugViewHierarchyTool.execute(arguments: arguments)
                case .debugViewBorders:
                    return try await debugViewBordersTool.execute(arguments: arguments)
                case .debugProcessStatus:
                    return try await debugProcessStatusTool.execute(arguments: arguments)
                // Memory diagnostic tools
                case .memoryLeaks:
                    return try await memoryLeaksTool.execute(arguments: arguments)
                case .memoryHeap:
                    return try await memoryHeapTool.execute(arguments: arguments)
                case .memoryVmmap:
                    return try await memoryVmmapTool.execute(arguments: arguments)
                case .memoryStringdups:
                    return try await memoryStringDupsTool.execute(arguments: arguments)
                case .memoryMallocHistory:
                    return try await memoryMallocHistoryTool.execute(arguments: arguments)
                // Crash symbolication
                case .symbolicateAddress:
                    return try await symbolicateAddressTool.execute(arguments: arguments)
                // macOS tools
                case .screenshotMacWindow:
                    return try await screenshotMacWindowTool.execute(arguments: arguments)
                // Interact tools (macOS Accessibility API)
                case .interactUITree:
                    return try await interactUITreeTool.execute(arguments: arguments)
                case .interactClick:
                    return try await interactClickTool.execute(arguments: arguments)
                case .interactSetValue:
                    return try await interactSetValueTool.execute(arguments: arguments)
                case .interactGetValue:
                    return try await interactGetValueTool.execute(arguments: arguments)
                case .interactMenu:
                    return try await interactMenuTool.execute(arguments: arguments)
                case .interactFocus:
                    return try await interactFocusTool.execute(arguments: arguments)
                case .interactKey:
                    return try await interactKeyTool.execute(arguments: arguments)
                case .interactFind:
                    return try await interactFindTool.execute(arguments: arguments)
                // Session tools
                case .setSessionDefaults:
                    return try await setSessionDefaultsTool.execute(arguments: arguments)
                case .showSessionDefaults:
                    return await showSessionDefaultsTool.execute(arguments: arguments)
                case .clearSessionDefaults:
                    return await clearSessionDefaultsTool.execute(arguments: arguments)
            }
        }

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
