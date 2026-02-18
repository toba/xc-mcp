import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("AddTargetToSynchronizedFolderTool Tests")
struct AddTargetToSynchronizedFolderToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        self.tempDir =
            FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AddTargetToSyncFolderToolTests-\(UUID().uuidString)"
            )
            .path
        self.pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test("Tool has correct properties")
    func toolProperties() {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_target_to_synchronized_folder")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["target_name"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("folder_path")))
                #expect(required.contains(.string("target_name")))
            }
        }
    }

    @Test("Validates required parameters")
    func validateRequiredParameters() throws {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "folder_path": .string("Sources"),
            ])
        }
    }

    @Test("Adds existing sync folder to second target")
    func addsExistingSyncFolderToSecondTarget() throws {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

        // Create a project with two targets
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        // Add a second target
        let xcodeproj = try XcodeProj(path: projectPath)
        let targetConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let targetConfigList = XCConfigurationList(
            buildConfigurations: [targetConfig], defaultConfigurationName: "Debug")
        xcodeproj.pbxproj.add(object: targetConfig)
        xcodeproj.pbxproj.add(object: targetConfigList)

        let secondTarget = PBXNativeTarget(
            name: "DiagnosticTarget",
            buildConfigurationList: targetConfigList,
            buildPhases: [],
            productType: .application
        )
        xcodeproj.pbxproj.add(object: secondTarget)
        try xcodeproj.pbxproj.rootProject()?.targets.append(secondTarget)

        // Add a synchronized folder to the first target
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        let firstTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" }!
        firstTarget.fileSystemSynchronizedGroups = [syncGroup]

        try xcodeproj.write(path: projectPath)

        // Now add the same sync folder to the second target
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("DiagnosticTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully added"))
            #expect(message.contains("DiagnosticTarget"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify both targets reference the same sync group
        let updated = try XcodeProj(path: projectPath)
        let updatedSecond = updated.pbxproj.nativeTargets.first {
            $0.name == "DiagnosticTarget"
        }
        #expect(updatedSecond?.fileSystemSynchronizedGroups?.count == 1)
        #expect(updatedSecond?.fileSystemSynchronizedGroups?.first?.path == "Sources")

        // Only one sync group object should exist
        #expect(updated.pbxproj.fileSystemSynchronizedRootGroups.count == 1)
    }

    @Test("Idempotent when already added")
    func idempotentWhenAlreadyAdded() throws {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        // Add a sync folder to the target
        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" }!
        target.fileSystemSynchronizedGroups = [syncGroup]
        try xcodeproj.write(path: projectPath)

        // Try to add again — should be idempotent
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sources"),
            "target_name": .string("AppTarget"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("already in target"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test("Fails when sync folder not found")
    func failsWhenSyncFolderNotFound() throws {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("NonExistent"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test("Fails when target not found")
    func failsWhenTargetNotFound() throws {
        let tool = AddTargetToSynchronizedFolderTool(pathUtility: pathUtility)

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
            ])
        }
    }
}
