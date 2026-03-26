import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct CreateGroupToolTests {
    @Test
    func `Tool creation`() {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "create_group")
        #expect(toolDefinition.description == "Create a new group in the project navigator")
    }

    @Test
    func `Create group with missing project path`() throws {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["group_name": Value.string("NewGroup")])
        }
    }

    @Test
    func `Create group with missing group name`() throws {
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: ["project_path": Value.string("/path/to/project.xcodeproj")],
            )
        }
    }

    @Test
    func `Create group in main group`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("NewGroup"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'NewGroup'"))
        #expect(message.contains("main group"))

        // Verify group was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let groups = xcodeproj.pbxproj.groups
        let newGroup = groups.first { $0.name == "NewGroup" }
        #expect(newGroup != nil)
    }

    @Test
    func `Create group with path`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("Sources"),
            "path": Value.string("Sources"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'Sources'"))

        // Verify group was created with path
        let xcodeproj = try XcodeProj(path: projectPath)
        let groups = xcodeproj.pbxproj.groups
        let sourcesGroup = groups.first { $0.name == "Sources" }
        #expect(sourcesGroup != nil)
        #expect(sourcesGroup?.path == "Sources")
    }

    @Test
    func `Create group in parent group`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))

        // First create a parent group
        let parentArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ParentGroup"),
        ]
        _ = try tool.execute(arguments: parentArgs)

        // Then create a child group
        let childArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("ChildGroup"),
            "parent_group": Value.string("ParentGroup"),
        ]

        let result = try tool.execute(arguments: childArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created group 'ChildGroup' in ParentGroup"))

        // Verify group hierarchy
        let xcodeproj = try XcodeProj(path: projectPath)
        let parentGroup = xcodeproj.pbxproj.groups.first { $0.name == "ParentGroup" }
        #expect(parentGroup != nil)

        let childInParent =
            parentGroup?.children.contains { element in
                if let group = element as? PBXGroup {
                    return group.name == "ChildGroup"
                }
                return false
            } ?? false
        #expect(childInParent == true)
    }

    @Test
    func `Create duplicate group`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("MyGroup"),
        ]

        // Create group first time
        _ = try tool.execute(arguments: args)

        // Try to create again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `Create group with non-existent parent`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "group_name": Value.string("NewGroup"),
            "parent_group": Value.string("NonExistentGroup"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
