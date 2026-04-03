import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveSynchronizedFolderExceptionToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "RemoveSyncFolderExceptionToolTests-\(UUID().uuidString)",
                )
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
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

    @Test
    func `Validates required parameters`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
            ])
        }
    }

    @Test
    func `Removes entire exception set when no file_name given`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message, _, _) = result.content.first {
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

    @Test
    func `Removes single file from exception set`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "file_name": .string("File1.swift"),
        ])

        if case let .text(message, _, _) = result.content.first {
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

    @Test
    func `Removes exception set when last file removed`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["OnlyFile.swift"], at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "file_name": .string("OnlyFile.swift"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Exception set was empty and has been removed"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets.isEmpty)
    }

    @Test
    func `Fails when sync folder not found`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("NonExistent"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test
    func `Fails when no exception set for target`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test
    func `Does not corrupt unrelated pbxproj sections`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
        )

        // Snapshot the pbxproj before the edit
        let pbxprojPath = (projectPath + "project.pbxproj").string
        let before = try String(contentsOfFile: pbxprojPath, encoding: .utf8)

        // Remove one file from the exception set
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
            "file_name": .string("File1.swift"),
        ])

        let after = try String(contentsOfFile: pbxprojPath, encoding: .utf8)

        // The only difference should be the removal of the File1.swift line
        let beforeLines = Set(before.components(separatedBy: "\n"))
        let afterLines = Set(after.components(separatedBy: "\n"))

        let removed = beforeLines.subtracting(afterLines)
        let added = afterLines.subtracting(beforeLines)

        // Only the File1.swift entry should have been removed; nothing added
        #expect(removed.count == 1, "Expected exactly one line removed, got \(removed)")
        #expect(
            removed.first?.trimmingCharacters(in: .whitespaces).hasPrefix("File1.swift") == true,
            "Removed line should be the File1.swift entry, got: \(removed)",
        )
        #expect(added.isEmpty, "No lines should be added, got: \(added)")

        // Verify the project still loads correctly
        let updated = try XcodeProj(path: projectPath)
        let exceptionSets = updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        #expect(exceptionSets.first?.membershipExceptions == ["File2.swift"])
    }

    @Test
    func `Does not corrupt unrelated sections when removing entire exception set`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift"], at: projectPath,
        )

        let pbxprojPath = (projectPath + "project.pbxproj").string
        let before = try String(contentsOfFile: pbxprojPath, encoding: .utf8)

        // Remove the entire exception set
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        let after = try String(contentsOfFile: pbxprojPath, encoding: .utf8)

        let beforeLines = before.components(separatedBy: "\n")
        let afterLines = after.components(separatedBy: "\n")

        // Lines removed should be: the exception set block (isa, membershipExceptions,
        // file entry, closing paren, target, opening/closing braces) plus the reference
        // in the sync group's exceptions array. No lines should be added.
        let added = Set(afterLines).subtracting(Set(beforeLines))
        #expect(added.isEmpty, "No lines should be added, got: \(added)")

        // Every line in `after` should exist in `before` (only removals, no modifications)
        for (i, line) in afterLines.enumerated() {
            #expect(
                beforeLines.contains(line),
                "Line \(i) in output was not in original: \(line)",
            )
        }

        // Verify the project still loads
        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets.isEmpty)
    }

    @Test
    func `Fails when file not in exception set`() throws {
        let tool = RemoveSynchronizedFolderExceptionTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["File1.swift"], at: projectPath,
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
