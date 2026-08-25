import MCP
import XCMCPCore

extension ToolRegistry {
    /// Debug tools.
    static let debug: [ToolRegistration] = [
    ToolRegistration("build_debug_macos", .debug, [.monolith, .debug]) { deps in
        let tool = BuildDebugMacOSTool(xcodebuildRunner: deps.xcodebuild, lldbRunner: deps.lldb, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("debug_attach_sim", .debug, [.monolith, .debug]) { deps in
        let tool = DebugAttachSimTool(lldbRunner: deps.lldb, simctlRunner: deps.simctl, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_breakpoint_add", .debug, [.monolith, .debug]) { deps in
        let tool = DebugBreakpointAddTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_breakpoint_remove", .debug, [.monolith, .debug]) { deps in
        let tool = DebugBreakpointRemoveTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_capture_backtrace", .debug, [.monolith, .debug]) { deps in
        let tool = DebugCaptureBacktraceTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_continue", .debug, [.monolith, .debug]) { deps in
        let tool = DebugContinueTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_detach", .debug, [.monolith, .debug]) { deps in
        let tool = DebugDetachTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_evaluate", .debug, [.monolith, .debug]) { deps in
        let tool = DebugEvaluateTool(lldbRunner: deps.lldb)
        return (tool.tool(), { call in
            guard let token = call.progressToken else {
                return try await tool.execute(arguments: call.arguments)
            }
            return try await tool.executeWithProgress(
                arguments: call.arguments, progressToken: token, notify: call.notify,
            )
        })
    },
    ToolRegistration("debug_lldb_command", .debug, [.monolith, .debug]) { deps in
        let tool = DebugLLDBCommandTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_memory", .debug, [.monolith, .debug]) { deps in
        let tool = DebugMemoryTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_process_status", .debug, [.monolith, .debug]) { deps in
        let tool = DebugProcessStatusTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_stack", .debug, [.monolith, .debug]) { deps in
        let tool = DebugStackTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_step", .debug, [.monolith, .debug]) { deps in
        let tool = DebugStepTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_symbol_lookup", .debug, [.monolith, .debug]) { deps in
        let tool = DebugSymbolLookupTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_threads", .debug, [.monolith, .debug]) { deps in
        let tool = DebugThreadsTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_variables", .debug, [.monolith, .debug]) { deps in
        let tool = DebugVariablesTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_view_borders", .debug, [.monolith, .debug]) { deps in
        let tool = DebugViewBordersTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_view_hierarchy", .debug, [.monolith, .debug]) { deps in
        let tool = DebugViewHierarchyTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("debug_watchpoint", .debug, [.monolith, .debug]) { deps in
        let tool = DebugWatchpointTool(lldbRunner: deps.lldb)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("memory_heap", .debug, [.monolith, .debug]) { deps in
        let tool = MemoryHeapTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("memory_leaks", .debug, [.monolith, .debug]) { deps in
        let tool = MemoryLeaksTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("memory_malloc_history", .debug, [.monolith, .debug]) { deps in
        let tool = MemoryMallocHistoryTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("memory_stringdups", .debug, [.monolith, .debug]) { deps in
        let tool = MemoryStringDupsTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("memory_vmmap", .debug, [.monolith, .debug]) { deps in
        let tool = MemoryVmmapTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("symbolicate_address", .debug, [.monolith, .debug]) { deps in
        let tool = SymbolicateAddressTool()
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_click", .interact, [.monolith, .debug]) { deps in
        let tool = InteractClickTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_find", .interact, [.monolith, .debug]) { deps in
        let tool = InteractFindTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_focus", .interact, [.monolith, .debug]) { deps in
        let tool = InteractFocusTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_get_value", .interact, [.monolith, .debug]) { deps in
        let tool = InteractGetValueTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_key", .interact, [.monolith, .debug]) { deps in
        let tool = InteractKeyTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_menu", .interact, [.monolith, .debug]) { deps in
        let tool = InteractMenuTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_set_value", .interact, [.monolith, .debug]) { deps in
        let tool = InteractSetValueTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("interact_ui_tree", .interact, [.monolith, .debug]) { deps in
        let tool = InteractUITreeTool(interactRunner: deps.interact)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}
