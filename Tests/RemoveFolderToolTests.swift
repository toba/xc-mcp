import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct RemoveFolderToolTests {
    private let tempDir = TemporaryDirectory.path
    private let pathUtility = PathUtility(basePath: TemporaryDirectory.path)

    @Test
    func `Tool has correct properties`() {
        let tool = RemoveFolderTool(pathUtility: pathUtility)
        let definition = tool.tool()

        #expect(definition.name == "remove_synchronized_folder")

        if case let .object(schemaDict) = definition.inputSchema,
           case let .object(props) = schemaDict["properties"]
        {
            #expect(props["project_path"] != nil)
            #expect(props["folder_path"] != nil)
        }
    }

    @Test
    func `Removes a folder a target references`() throws {
        let tool = RemoveFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully removed"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedRootGroups.isEmpty)

        let target = try #require(updated.pbxproj.nativeTargets.first { $0.name == "AppTarget" })
        #expect((target.fileSystemSynchronizedGroups ?? []).isEmpty)
    }

    @Test
    func `Removes the exception sets the folder owns`() throws {
        let tool = RemoveFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
            membershipExceptions: ["Skipped.swift"],
            at: projectPath,
        )

        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
        ])

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedRootGroups.isEmpty)
        #expect(updated.pbxproj.fileSystemSynchronizedBuildFileExceptionSets.isEmpty)
    }

    @Test
    func `Removes a folder named by its full path`() throws {
        let tool = RemoveFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithAmbiguousSyncFolders(
            name: "TestProject", modules: ["Core"], at: projectPath,
        )

        // The folder stores the leaf 'Sources' under a parent group with path 'Core'.
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Core/Sources"),
        ])

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedRootGroups.isEmpty)
    }

    @Test
    func `Refuses a leaf name two folders share`() throws {
        let tool = RemoveFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithAmbiguousSyncFolders(
            name: "TestProject", modules: ["Core", "Kit"], at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("Sources"),
            ])
        }

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.fileSystemSynchronizedRootGroups.count == 2)
    }

    @Test
    func `Reports a folder the project does not hold`() throws {
        let tool = RemoveFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }
}
