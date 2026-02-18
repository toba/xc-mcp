import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("AddSynchronizedFolderExceptionTool Tests")
struct AddSynchronizedFolderExceptionToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        self.tempDir =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AddSyncFolderExceptionToolTests-\(UUID().uuidString)"
            )
            .path
        self.pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test("Tool has correct properties")
    func toolProperties() {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_synchronized_folder_exception")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["target_name"] != nil)
                #expect(props["files"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 4)
            }
        }
    }

    @Test("Validates required parameters")
    func validateRequiredParameters() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
                "target_name": .string("App"),
            ])
        }
    }

    @Test("Validates non-empty files array")
    func validatesNonEmptyFilesArray() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("AppTarget"),
                "files": .array([]),
            ])
        }
    }

    @Test("Adds membership exceptions to sync folder")
    func addsMembershipExceptions() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        // Add a sync folder
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        try xcodeproj.write(path: projectPath)

        // Add exceptions
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "files": .array([.string("DiagnosticApp.swift"), .string("TestHelper.swift")]),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully added membership exceptions"))
            #expect(message.contains("DiagnosticApp.swift"))
            #expect(message.contains("TestHelper.swift"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the exception set was created
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        #expect(exceptionSets.first?.membershipExceptions?.count == 2)
        #expect(exceptionSets.first?.membershipExceptions?.contains("DiagnosticApp.swift") == true)
        #expect(exceptionSets.first?.membershipExceptions?.contains("TestHelper.swift") == true)
        #expect(exceptionSets.first?.target?.name == "AppTarget")

        // Verify the exception set is attached to the sync group
        let updatedSyncGroups = updated.pbxproj.fileSystemSynchronizedRootGroups
        #expect(updatedSyncGroups.first?.exceptions?.count == 1)
    }

    @Test("Fails when sync folder not found")
    func failsWhenSyncFolderNotFound() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("NonExistent"),
                "target_name": .string("AppTarget"),
                "files": .array([.string("file.swift")]),
            ])
        }
    }

    @Test("Fails when target not found")
    func failsWhenTargetNotFound() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        // Add a sync folder
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        try xcodeproj.write(path: projectPath)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("NonExistentTarget"),
                "files": .array([.string("file.swift")]),
            ])
        }
    }
}
