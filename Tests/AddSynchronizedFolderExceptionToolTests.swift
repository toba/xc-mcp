import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AddSynchronizedFolderExceptionToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "AddSyncFolderExceptionToolTests-\(UUID().uuidString)",
                )
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
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

    @Test
    func `Validates required parameters`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
                "target_name": .string("App"),
            ])
        }
    }

    @Test
    func `Validates non-empty files array`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("AppTarget"),
                "files": .array([]),
            ])
        }
    }

    @Test
    func `Adds membership exceptions to sync folder`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        // Add a sync folder
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources",
        )
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

        if case let .text(message, _, _) = result.content.first {
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

    @Test
    func `Appends to existing exception set instead of creating duplicate`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
        )

        // Add more files to the same target — should append, not create a second set
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "files": .array([.string("File3.swift"), .string("File4.swift")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added membership exceptions"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify only one exception set exists with all four files
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        #expect(exceptionSets.first?.membershipExceptions?.count == 4)
        #expect(exceptionSets.first?.membershipExceptions?.contains("File1.swift") == true)
        #expect(exceptionSets.first?.membershipExceptions?.contains("File3.swift") == true)
    }

    @Test
    func `Skips duplicate files when appending to existing exception set`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
        )

        // Try to add a file that already exists
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "files": .array([.string("File1.swift")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("already in the exception set"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify no duplicates were added
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        #expect(exceptionSets.first?.membershipExceptions?.count == 2)
    }

    @Test
    func `Fails when sync folder not found`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("NonExistent"),
                "target_name": .string("AppTarget"),
                "files": .array([.string("file.swift")]),
            ])
        }
    }

    @Test
    func `Fails when target not found`() throws {
        let tool = AddSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        // Add a sync folder
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources",
        )
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
