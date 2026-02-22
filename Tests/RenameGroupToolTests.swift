import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite("RenameGroupTool Tests")
struct RenameGroupToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RenameGroupTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "rename_group")
        #expect(toolDefinition.description == "Rename a group in the Xcode project hierarchy")
    }

    @Test("Rename group with missing parameters")
    func renameGroupWithMissingParameters() throws {
        let tool = RenameGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "group_path": Value.string("Sources/App"),
                "new_name": Value.string("NewApp"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_name": Value.string("NewApp"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "group_path": Value.string("Sources/App"),
            ])
        }
    }

    @Test("Rename existing group")
    func renameExistingGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a group to the project
        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let childGroup = PBXGroup(
            children: [], sourceTree: .group, name: "OldGroup", path: "OldGroup",
        )
        xcodeproj.pbxproj.add(object: childGroup)
        mainGroup.children.append(childGroup)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("OldGroup"),
            "new_name": Value.string("NewGroup"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed group 'OldGroup' to 'NewGroup'"))

        // Verify group was renamed
        let updatedProj = try XcodeProj(path: projectPath)
        let updatedMainGroup = try #require(try updatedProj.pbxproj.rootProject()?.mainGroup)
        let renamedGroup = updatedMainGroup.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "NewGroup"
        }
        #expect(renamedGroup != nil)
        #expect(renamedGroup?.path == "NewGroup")
    }

    @Test("Rename nested group")
    func renameNestedGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add nested groups: Sources/OldModule
        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let sourcesGroup = PBXGroup(
            children: [], sourceTree: .group, name: "Sources", path: "Sources",
        )
        xcodeproj.pbxproj.add(object: sourcesGroup)
        mainGroup.children.append(sourcesGroup)
        let moduleGroup = PBXGroup(
            children: [], sourceTree: .group, name: "OldModule", path: "OldModule",
        )
        xcodeproj.pbxproj.add(object: moduleGroup)
        sourcesGroup.children.append(moduleGroup)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let tool = RenameGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("Sources/OldModule"),
            "new_name": Value.string("NewModule"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed group 'OldModule' to 'NewModule'"))

        // Verify nested group was renamed
        let updatedProj = try XcodeProj(path: projectPath)
        let updatedMainGroup = try #require(try updatedProj.pbxproj.rootProject()?.mainGroup)
        let updatedSources = updatedMainGroup.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "Sources"
        }
        let renamedModule = updatedSources?.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "NewModule"
        }
        #expect(renamedModule != nil)
    }

    @Test("Rename non-existent group")
    func renameNonExistentGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RenameGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("NonExistent"),
            "new_name": Value.string("NewGroup"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}
