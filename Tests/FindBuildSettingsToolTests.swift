import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct FindBuildSettingsToolTests {
    /// Builds a project with a target, then injects a project-level build setting on both the Debug
    /// and Release project configurations. Returns the resolved project path inside `tempDir`.
    private func makeProjectWithProjectLevelSetting(
        tempDir: URL,
        setting: String,
        value: BuildSetting,
    ) throws -> Path {
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let project = xcodeproj.pbxproj.rootObject!
        for config in project.buildConfigurationList!.buildConfigurations {
            config.buildSettings[setting] = value
        }
        try xcodeproj.write(path: projectPath)
        return projectPath
    }

    @Test func `find build settings tool creation`() {
        let tool = FindBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "find_build_settings")
        #expect(toolDefinition.description?.contains("[project]") == true)
    }

    @Test func `find build settings requires project path`() throws {
        let tool = FindBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["settings": .array([.string("OTHER_LDFLAGS")])])
        }
    }

    @Test func `find build settings requires non-empty settings`() throws {
        let tool = FindBuildSettingsTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path/to/project.xcodeproj"),
                "settings": .array([]),
            ])
        }
    }

    @Test func `find build settings reports project-level match`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A malformed OTHER_LDFLAGS on the project level is inherited by every target — exactly the
        // invisible-inheritance case this tool must surface.
        let projectPath = try makeProjectWithProjectLevelSetting(
            tempDir: tempDir,
            setting: "OTHER_LDFLAGS",
            value: .string("-Wl -no_exported_symbols"),
        )

        let tool = FindBuildSettingsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "settings": .array([.string("OTHER_LDFLAGS")]),
        ])

        #expect(result.content.count == 1)
        guard case let .text(content, _, _) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[project] [Debug] OTHER_LDFLAGS = -Wl -no_exported_symbols"))
        #expect(content.contains("[project] [Release] OTHER_LDFLAGS = -Wl -no_exported_symbols"))
    }

    @Test func `find build settings project-level respects value filter and configuration`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = try makeProjectWithProjectLevelSetting(
            tempDir: tempDir,
            setting: "OTHER_LDFLAGS",
            value: .string("-Wl -no_exported_symbols"),
        )

        let tool = FindBuildSettingsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "settings": .array([.string("OTHER_LDFLAGS")]),
            "values": .array([.string("no_exported_symbols")]),
            "configuration": .string("Release"),
        ])

        guard case let .text(content, _, _) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[project] [Release] OTHER_LDFLAGS"))
        #expect(!content.contains("[Debug]"))
        #expect(content.contains(": 1 match"))
    }
}
