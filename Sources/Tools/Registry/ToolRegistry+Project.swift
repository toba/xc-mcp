import MCP
import XCMCPCore

extension ToolRegistry {
    /// Project tools, part 1.
    static let project1: [ToolRegistration] = [
    ToolRegistration("add_app_extension", .project, [.monolith, .project]) { deps in
        let tool = AddAppExtensionTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_build_phase", .project, [.monolith, .project]) { deps in
        let tool = AddBuildPhaseTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_copy_files_phase", .project, [.monolith, .project]) { deps in
        let tool = AddCopyFilesPhase(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_dependency", .project, [.monolith, .project]) { deps in
        let tool = AddDependencyTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_file", .project, [.monolith, .project]) { deps in
        let tool = AddFileTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_framework", .project, [.monolith, .project]) { deps in
        let tool = AddFrameworkTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_package_product", .project, [.monolith, .project]) { deps in
        let tool = AddPackageProductTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_storekit_config", .project, [.monolith, .project]) { deps in
        let tool = AddStoreKitConfigTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_swift_package", .project, [.monolith, .project]) { deps in
        let tool = AddSwiftPackageTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_synchronized_folder", .project, [.monolith, .project]) { deps in
        let tool = AddFolderTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_synchronized_folder_exception", .project, [.monolith, .project]) { deps in
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_synchronized_folder_phase_membership", .project, [.monolith, .project]) { deps in
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_target", .project, [.monolith, .project]) { deps in
        let tool = AddTargetTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_target_to_synchronized_folder", .project, [.monolith, .project]) { deps in
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_target_to_test_plan", .project, [.monolith, .project]) { deps in
        let tool = AddTargetToTestPlanTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_test_plan_to_scheme", .project, [.monolith, .project]) { deps in
        let tool = AddTestPlanToSchemeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("add_to_copy_files_phase", .project, [.monolith, .project]) { deps in
        let tool = AddToCopyFilesPhase(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("audit_swift_packages", .project, [.monolith, .project]) { deps in
        let tool = AuditSwiftPackagesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("create_group", .project, [.monolith, .project]) { deps in
        let tool = CreateGroupTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("create_scheme", .project, [.monolith, .project]) { deps in
        let tool = CreateSchemeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("create_test_plan", .project, [.monolith, .project]) { deps in
        let tool = CreateTestPlanTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("create_xcodeproj", .project, [.monolith, .project]) { deps in
        let tool = CreateXcodeprojTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("dump_pif", .project, [.monolith, .project]) { deps in
        let tool = DumpPIFTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("duplicate_target", .project, [.monolith, .project]) { deps in
        let tool = DuplicateTargetTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("find_build_settings", .project, [.monolith, .project]) { deps in
        let tool = FindBuildSettingsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("find_link_flag", .project, [.monolith, .project]) { deps in
        let tool = FindLinkFlagTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("get_build_settings", .project, [.monolith, .project]) { deps in
        let tool = GetBuildSettingsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_build_configurations", .project, [.monolith, .project]) { deps in
        let tool = ListBuildConfigurationsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_copy_files_phases", .project, [.monolith, .project]) { deps in
        let tool = ListCopyFilesPhases(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_dependencies", .project, [.monolith, .project]) { deps in
        let tool = ListDependenciesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_document_types", .project, [.monolith, .project]) { deps in
        let tool = ListDocumentTypesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_files", .project, [.monolith, .project]) { deps in
        let tool = ListFilesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_frameworks_phase", .project, [.monolith, .project]) { deps in
        let tool = ListFrameworksPhaseTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_groups", .project, [.monolith, .project]) { deps in
        let tool = ListGroupsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_package_products", .project, [.monolith, .project]) { deps in
        let tool = ListPackageProductsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_run_script_phases", .project, [.monolith, .project]) { deps in
        let tool = ListRunScriptPhasesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_swift_packages", .project, [.monolith, .project]) { deps in
        let tool = ListSwiftPackagesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_synchronized_folder_exceptions", .project, [.monolith, .project]) { deps in
        let tool = ListSynchronizedFolderExceptionsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_targets", .project, [.monolith, .project]) { deps in
        let tool = ListTargetsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_test_plans", .project, [.monolith, .project]) { deps in
        let tool = ListTestPlansTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ]

    /// Project tools, part 2.
    static let project2: [ToolRegistration] = [
    ToolRegistration("list_type_identifiers", .project, [.monolith, .project]) { deps in
        let tool = ListTypeIdentifiersTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("list_url_types", .project, [.monolith, .project]) { deps in
        let tool = ListURLTypesTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("manage_document_type", .project, [.monolith, .project]) { deps in
        let tool = ManageDocumentTypeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("manage_type_identifier", .project, [.monolith, .project]) { deps in
        let tool = ManageTypeIdentifierTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("manage_url_type", .project, [.monolith, .project]) { deps in
        let tool = ManageURLTypeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("move_file", .project, [.monolith, .project]) { deps in
        let tool = MoveFileTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("move_group", .project, [.monolith, .project]) { deps in
        let tool = MoveGroupTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_app_extension", .project, [.monolith, .project]) { deps in
        let tool = RemoveAppExtensionTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_build_setting", .project, [.monolith, .project]) { deps in
        let tool = RemoveBuildSettingTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_copy_files_phase", .project, [.monolith, .project]) { deps in
        let tool = RemoveCopyFilesPhase(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_dependency", .project, [.monolith, .project]) { deps in
        let tool = RemoveDependencyTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_file", .project, [.monolith, .project]) { deps in
        let tool = RemoveFileTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_framework", .project, [.monolith, .project]) { deps in
        let tool = RemoveFrameworkTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_from_copy_files_phase", .project, [.monolith, .project]) { deps in
        let tool = RemoveFromCopyFilesPhase(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_group", .project, [.monolith, .project]) { deps in
        let tool = RemoveGroupTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_package_product", .project, [.monolith, .project]) { deps in
        let tool = RemovePackageProductTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_run_script_phase", .project, [.monolith, .project]) { deps in
        let tool = RemoveRunScriptPhase(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_subproject", .project, [.monolith, .project]) { deps in
        let tool = RemoveSubprojectTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_swift_package", .project, [.monolith, .project]) { deps in
        let tool = RemoveSwiftPackageTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_synchronized_folder", .project, [.monolith, .project]) { deps in
        let tool = RemoveFolderTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_synchronized_folder_exception", .project, [.monolith, .project]) { deps in
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_target", .project, [.monolith, .project]) { deps in
        let tool = RemoveTargetTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_target_from_synchronized_folder", .project, [.monolith, .project]) { deps in
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_target_from_test_plan", .project, [.monolith, .project]) { deps in
        let tool = RemoveTargetFromTestPlanTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("remove_test_plan_from_scheme", .project, [.monolith, .project]) { deps in
        let tool = RemoveTestPlanFromSchemeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("rename_group", .project, [.monolith, .project]) { deps in
        let tool = RenameGroupTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("rename_scheme", .project, [.monolith, .project]) { deps in
        let tool = RenameSchemeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("rename_target", .project, [.monolith, .project]) { deps in
        let tool = RenameTargetTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("repair_project", .project, [.monolith, .project]) { deps in
        let tool = RepairProjectTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("resolve_packages", .project, [.monolith, .project]) { deps in
        let tool = ResolvePackagesTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("scaffold_module", .project, [.monolith, .project]) { deps in
        let tool = ScaffoldModuleTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("search_test_plans", .project, [.monolith, .project]) { deps in
        let tool = SearchTestPlansTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_build_setting", .project, [.monolith, .project]) { deps in
        let tool = SetBuildSettingTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_copy_files_phase_subpath", .project, [.monolith, .project]) { deps in
        let tool = SetCopyFilesPhaseSubpath(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_framework_merge_attribute", .project, [.monolith, .project]) { deps in
        let tool = SetFrameworkMergeAttributeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_run_script_phase_io", .project, [.monolith, .project]) { deps in
        let tool = SetRunScriptPhaseIOTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_scheme_storekit_config", .project, [.monolith, .project]) { deps in
        let tool = SetSchemeStoreKitConfigTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_test_plan_options", .project, [.monolith, .project]) { deps in
        let tool = SetTestPlanOptionsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_test_plan_skipped_tags", .project, [.monolith, .project]) { deps in
        let tool = SetTestPlanSkippedTagsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_test_plan_skipped_tests", .project, [.monolith, .project]) { deps in
        let tool = SetTestPlanSkippedTestsTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ]

    /// Project tools, part 3.
    static let project3: [ToolRegistration] = [
    ToolRegistration("set_test_plan_target_enabled", .project, [.monolith, .project]) { deps in
        let tool = SetTestPlanTargetEnabledTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_test_plan_target_parallelizable", .project, [.monolith, .project]) { deps in
        let tool = SetTestPlanTargetParallelizableTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("set_test_target_application", .project, [.monolith, .project]) { deps in
        let tool = SetTestTargetApplicationTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("show_package_resolution", .project, [.monolith, .project]) { deps in
        let tool = ShowPackageResolutionTool(pathUtility: deps.paths)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("update_swift_package", .project, [.monolith, .project]) { deps in
        let tool = UpdateSwiftPackageTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("validate_project", .project, [.monolith, .project]) { deps in
        let tool = ValidateProjectTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("validate_scheme", .project, [.monolith, .project]) { deps in
        let tool = ValidateSchemeTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("why_target_id", .project, [.monolith, .project]) { deps in
        let tool = WhyTargetIDTool(pathUtility: deps.paths)
        return (tool.tool(), { try tool.execute(arguments: $0.arguments) })
    },
    ]
}
