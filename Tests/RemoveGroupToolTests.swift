import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("RemoveGroupTool Tests")
struct RemoveGroupToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RemoveGroupTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_group")
        #expect(toolDefinition.description == "Remove a group from the project navigator")
    }

    @Test("Missing project path")
    func missingProjectPath() throws {
        let tool = RemoveGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["group_name": Value.string("SomeGroup")])
        }
    }

    @Test("Missing group name")
    func missingGroupName() throws {
        let tool = RemoveGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("/path/to/project.xcodeproj")]
            )
        }
    }

    @Test("Remove empty group")
    func removeEmptyGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a group first
        let createTool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("EmptyGroup"),
        ])

        // Remove it
        let removeTool = RemoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("EmptyGroup"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed group 'EmptyGroup'"))

        // Verify group is gone
        let xcodeproj = try XcodeProj(path: projectPath)
        let found = xcodeproj.pbxproj.groups.first { $0.name == "EmptyGroup" }
        #expect(found == nil)
    }

    @Test("Remove non-existent group")
    func removeNonExistentGroup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RemoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("DoesNotExist"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Remove group with children fails without recursive")
    func removeGroupWithChildrenFailsWithoutRecursive() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create parent and child groups
        let createTool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
        ])
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ChildGroup"),
            "parent_group": Value.string("ParentGroup"),
        ])

        // Try to remove parent without recursive
        let removeTool = RemoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("has 1 children"))
        #expect(message.contains("recursive=true"))
    }

    @Test("Remove group with children recursively")
    func removeGroupWithChildrenRecursively() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create parent and child groups
        let createTool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
        ])
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ChildGroup"),
            "parent_group": Value.string("ParentGroup"),
        ])

        // Remove parent with recursive
        let removeTool = RemoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
            "recursive": Value.bool(true),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed group 'ParentGroup'"))

        // Verify both groups are gone
        let xcodeproj = try XcodeProj(path: projectPath)
        #expect(!xcodeproj.pbxproj.groups.contains { $0.name == "ParentGroup" })
        #expect(!xcodeproj.pbxproj.groups.contains { $0.name == "ChildGroup" })
    }

    @Test("Remove group by path")
    func removeGroupByPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create nested groups
        let createTool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("Sources"),
        ])
        _ = try createTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("Models"),
            "parent_group": Value.string("Sources"),
        ])

        // Remove by path
        let removeTool = RemoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("Sources/Models"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed group 'Sources/Models'"))

        // Verify Models is gone but Sources remains
        let xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.groups.contains { $0.name == "Sources" })
        #expect(!xcodeproj.pbxproj.groups.contains { $0.name == "Models" })
    }
}
