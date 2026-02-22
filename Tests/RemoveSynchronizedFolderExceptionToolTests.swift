import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("RemoveSynchronizedFolderExceptionTool Tests")
struct RemoveSynchronizedFolderExceptionToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RemoveSyncFolderExceptionToolTests-\(UUID().uuidString)"
            )
            .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test("Tool has correct properties")
    func toolProperties() {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "remove_synchronized_folder_exception")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["target_name"] != nil)
                #expect(props["file_name"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
            }
        }
    }

    @Test("Validates required parameters")
    func validateRequiredParameters() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
            ])
        }
    }

    @Test("Removes entire exception set when no file_name given")
    func removesEntireExceptionSet() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Removed exception set"))
            #expect(message.contains("AppTarget"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify exception set was removed
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.isEmpty)
        let updatedSyncGroups = updated.pbxproj.fileSystemSynchronizedRootGroups
        #expect(updatedSyncGroups.first?.exceptions?.isEmpty != false)
    }

    @Test("Removes single file from exception set")
    func removesSingleFile() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "file_name": .string("File1.swift"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Removed 'File1.swift'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify only one file remains
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        #expect(exceptionSets.first?.membershipExceptions == ["File2.swift"])
    }

    @Test("Removes exception set when last file removed")
    func removesExceptionSetWhenLastFileRemoved() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["OnlyFile.swift"], at: projectPath
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "file_name": .string("OnlyFile.swift"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Exception set was empty and has been removed"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets.isEmpty)
    }

    @Test("Fails when sync folder not found")
    func failsWhenSyncFolderNotFound() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("NonExistent"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test("Fails when no exception set for target")
    func failsWhenNoExceptionSetForTarget() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            at: projectPath
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test("Fails when file not in exception set")
    func failsWhenFileNotInExceptionSet() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift"], at: projectPath
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("AppTarget"),
                "file_name": .string("NonExistent.swift"),
            ])
        }
    }
}
