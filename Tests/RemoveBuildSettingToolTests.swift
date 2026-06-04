import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveBuildSettingToolTests {
    @Test
    func `Tool creation`() {
        let tool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_build_setting")
        #expect(toolDefinition.description?.contains("Delete a build setting") == true)
    }

    @Test
    func `Missing required parameters throws`() throws {
        let tool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("FOO"),
            ])
        }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/x.xcodeproj"),
                "setting_name": Value.string("FOO"),
            ])
        }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/x.xcodeproj"),
                "configuration": Value.string("Debug"),
            ])
        }
    }

    @Test
    func `Remove existing setting from single configuration`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Seed a setting on both Debug and Release using SetBuildSettingTool.
        let setTool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try setTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("All"),
            "setting_name": Value.string("DEVELOPMENT_ASSET_PATHS"),
            "setting_value": Value.string("\"App/Preview Content\""),
        ])

        // Remove from Release only.
        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Release"),
            "setting_name": Value.string("DEVELOPMENT_ASSET_PATHS"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Removed 'DEVELOPMENT_ASSET_PATHS'"))
        #expect(message.contains("Release"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let debugConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        let releaseConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Release"
        }

        // Debug still has it, Release does not.
        #expect(debugConfig?.buildSettings["DEVELOPMENT_ASSET_PATHS"] != nil)
        #expect(releaseConfig?.buildSettings["DEVELOPMENT_ASSET_PATHS"] == nil)
    }

    @Test
    func `Remove from all configurations`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let setTool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try setTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("All"),
            "setting_name": Value.string("FOO"),
            "setting_value": Value.string("bar"),
        ])

        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("All"),
            "setting_name": Value.string("FOO"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Removed 'FOO'"))
        #expect(message.contains("Debug"))
        #expect(message.contains("Release"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        for config in target?.buildConfigurationList?.buildConfigurations ?? [] {
            #expect(config.buildSettings["FOO"] == nil)
        }
    }

    @Test
    func `Remove no-op when setting absent`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("NEVER_SET"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("was not set"))
        #expect(message.contains("no changes made"))
    }

    @Test
    func `Remove with non-existent target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Nope"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("FOO"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `Remove with non-existent configuration`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Beta"),
            "setting_name": Value.string("FOO"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Configuration 'Beta' not found"))
    }

    @Test
    func `Remove project-level setting`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let setTool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try setTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("CUSTOM_FLAG"),
            "setting_value": Value.string("YES"),
        ])

        let removeTool = RemoveBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("CUSTOM_FLAG"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Removed 'CUSTOM_FLAG'"))
        #expect(message.contains("project"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let projectConfig = xcodeproj.pbxproj.rootObject?.buildConfigurationList?
            .buildConfigurations.first { $0.name == "Debug" }
        #expect(projectConfig?.buildSettings["CUSTOM_FLAG"] == nil)
    }
}
