import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveTargetFromSynchronizedFolderToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "RemoveTargetFromSyncFolderToolTests-\(UUID().uuidString)",
                )
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)
        let definition = tool.tool()

        #expect(definition.name == "remove_target_from_synchronized_folder")

        let schema = definition.inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["target_name"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
            }
        }
    }

    @Test
    func `Validates required parameters`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
            ])
        }
    }

    @Test
    func `Removes target from synchronized folder`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            at: projectPath,
        )

        // Remove target from sync folder
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully removed"))
            #expect(message.contains("AppTarget"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify target no longer references the sync group
        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = updated.pbxproj.nativeTargets.first { $0.name == "AppTarget" }
        let syncGroups = updatedTarget?.fileSystemSynchronizedGroups ?? []
        #expect(syncGroups.isEmpty)
    }

    @Test
    func `Cleans up exception sets when removing target`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["SomeFile.swift"], at: projectPath,
        )

        // Remove target
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully removed"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify exception sets are cleaned up
        let updated = try XcodeProj(path: projectPath)
        let updatedSync = updated.pbxproj.fileSystemSynchronizedRootGroups.first {
            $0.path == "Sources"
        }
        let exceptions = updatedSync?.exceptions ?? []
        #expect(exceptions.isEmpty)
    }

    @Test
    func `Returns message when target does not reference folder`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        // Add a sync folder but don't link it to the target
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources",
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        try xcodeproj.write(path: projectPath)

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("does not reference"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Fails when sync folder not found`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

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
    func `Fails when target not found`() throws {
        let tool = RemoveTargetFromSynchronizedFolderTool(pathUtility: pathUtility)

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
            ])
        }
    }
}
