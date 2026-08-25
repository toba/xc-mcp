import MCP
import XCMCPCore

extension ToolRegistry {
    /// Strings tools.
    static let strings: [ToolRegistration] = [
    ToolRegistration("xcstrings_add_translation", .strings, [.strings]) { deps in
        let tool = XCStringsAddTranslationTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_add_translations", .strings, [.strings]) { deps in
        let tool = XCStringsAddTranslationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_batch_add_translations", .strings, [.strings]) { deps in
        let tool = XCStringsBatchAddTranslationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_batch_check_keys", .strings, [.strings]) { deps in
        let tool = XCStringsBatchCheckKeysTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_batch_list_stale", .strings, [.strings]) { deps in
        let tool = XCStringsBatchListStaleTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_batch_stats_coverage", .strings, [.strings]) { deps in
        let tool = XCStringsBatchStatsCoverageTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_batch_update_translations", .strings, [.strings]) { deps in
        let tool = XCStringsBatchUpdateTranslationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_check_coverage", .strings, [.strings]) { deps in
        let tool = XCStringsCheckCoverageTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_check_key", .strings, [.strings]) { deps in
        let tool = XCStringsCheckKeyTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_check_untranslated", .strings, [.strings]) { deps in
        let tool = XCStringsCheckUntranslatedTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_create_file", .strings, [.strings]) { deps in
        let tool = XCStringsCreateFileTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_delete_key", .strings, [.strings]) { deps in
        let tool = XCStringsDeleteKeyTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_delete_translation", .strings, [.strings]) { deps in
        let tool = XCStringsDeleteTranslationTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_delete_translations", .strings, [.strings]) { deps in
        let tool = XCStringsDeleteTranslationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_get_key", .strings, [.strings]) { deps in
        let tool = XCStringsGetKeyTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_get_source_language", .strings, [.strings]) { deps in
        let tool = XCStringsGetSourceLanguageTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_list_keys", .strings, [.strings]) { deps in
        let tool = XCStringsListKeysTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_list_languages", .strings, [.strings]) { deps in
        let tool = XCStringsListLanguagesTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_list_stale", .strings, [.strings]) { deps in
        let tool = XCStringsListStaleTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_list_untranslated", .strings, [.strings]) { deps in
        let tool = XCStringsListUntranslatedTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_promote_literals", .strings, [.strings]) { deps in
        let tool = XCStringsPromoteLiteralsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_rename_key", .strings, [.strings]) { deps in
        let tool = XCStringsRenameKeyTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_stats_coverage", .strings, [.strings]) { deps in
        let tool = XCStringsStatsCoverageTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_stats_progress", .strings, [.strings]) { deps in
        let tool = XCStringsStatsProgressTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_update_translation", .strings, [.strings]) { deps in
        let tool = XCStringsUpdateTranslationTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("xcstrings_update_translations", .strings, [.strings]) { deps in
        let tool = XCStringsUpdateTranslationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ]
}
