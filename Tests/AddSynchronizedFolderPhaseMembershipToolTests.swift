import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AddSynchronizedFolderPhaseMembershipToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "AddSyncFolderPhaseMembershipToolTests-\(UUID().uuidString)",
                )
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(
            atPath: tempDir, withIntermediateDirectories: true,
        )
    }

    /// Helper: create a project with one target that has a sync folder and a Copy Files phase.
    private func makeProject(
        copyPhaseName: String? = nil,
        dstPath: String? = nil,
        existingMembership: [String]? = nil,
    ) throws -> Path {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "AppTarget", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" }!

        // Add the sync group "DefaultStyles"
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "DefaultStyles", name: "DefaultStyles",
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        target.fileSystemSynchronizedGroups = [syncGroup]

        // Add a Copy Files phase
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: dstPath,
            dstSubfolderSpec: .resources,
            name: copyPhaseName,
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)

        // Optional: pre-existing exception set
        if let existingMembership {
            let exceptionSet = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet(
                buildPhase: copyPhase,
                membershipExceptions: existingMembership,
                attributesByRelativePath: nil,
            )
            xcodeproj.pbxproj.add(object: exceptionSet)
            syncGroup.exceptions = [exceptionSet]
        }

        try xcodeproj.write(path: projectPath)
        return projectPath
    }

    @Test
    func `Tool has correct properties`() {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        #expect(tool.tool().name == "add_synchronized_folder_phase_membership")
    }

    @Test
    func `Validates required parameters`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("x.xcodeproj"),
                "folder_path": .string("DefaultStyles"),
                "target_name": .string("AppTarget"),
            ])
        }
    }

    @Test
    func `Validates non-empty files array`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(dstPath: "docx")
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("DefaultStyles"),
                "target_name": .string("AppTarget"),
                "files": .array([]),
            ])
        }
    }

    @Test
    func `Creates exception set on first add when located by dst_path`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(dstPath: "docx")

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("DefaultStyles"),
            "target_name": .string("AppTarget"),
            "dst_path": .string("docx"),
            "files": .array([.string("word-16.xml"), .string("word-16-custom.xml")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added"))
            #expect(message.contains("word-16.xml"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        let sets = updated.pbxproj.fileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
        #expect(sets.count == 1)
        let set = sets[0]
        #expect(set.membershipExceptions?.contains("word-16.xml") == true)
        #expect(set.membershipExceptions?.contains("word-16-custom.xml") == true)
        #expect(set.buildPhase is PBXCopyFilesBuildPhase)

        // Verify it's attached to the sync group
        let syncGroup = updated.pbxproj.fileSystemSynchronizedRootGroups
            .first { $0.path == "DefaultStyles" }!
        #expect(syncGroup.exceptions?.count == 1)
    }

    @Test
    func `Appends to existing exception set instead of creating duplicate`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(
            dstPath: "docx",
            existingMembership: ["word-16.xml", "word-16-custom.xml"],
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("DefaultStyles"),
            "target_name": .string("AppTarget"),
            "dst_path": .string("docx"),
            "files": .array([.string("word-16-vellum.xml")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        let sets = updated.pbxproj.fileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet
        #expect(sets.count == 1)
        #expect(sets[0].membershipExceptions?.count == 3)
        #expect(sets[0].membershipExceptions?.contains("word-16-vellum.xml") == true)
    }

    @Test
    func `Skips duplicate files`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(
            dstPath: "docx",
            existingMembership: ["word-16.xml"],
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("DefaultStyles"),
            "target_name": .string("AppTarget"),
            "dst_path": .string("docx"),
            "files": .array([.string("word-16.xml")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("already in"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Locates phase by name when phase_name is provided`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(
            copyPhaseName: "Bundle Templates", dstPath: "docx",
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("DefaultStyles"),
            "target_name": .string("AppTarget"),
            "phase_name": .string("Bundle Templates"),
            "files": .array([.string("word-16.xml")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Bundle Templates"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Falls back to single Copy Files phase when no name or dst_path`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(dstPath: "docx")

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("DefaultStyles"),
            "target_name": .string("AppTarget"),
            "files": .array([.string("word-16.xml")]),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully added"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Fails when phase_name does not match`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(dstPath: "docx")

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("DefaultStyles"),
                "target_name": .string("AppTarget"),
                "phase_name": .string("Nonexistent"),
                "files": .array([.string("x.xml")]),
            ])
        }
    }

    @Test
    func `Fails when dst_path matches no Copy Files phase`() throws {
        let tool = AddSynchronizedFolderPhaseMembershipTool(pathUtility: pathUtility)
        let projectPath = try makeProject(dstPath: "docx")

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("DefaultStyles"),
                "target_name": .string("AppTarget"),
                "dst_path": .string("elsewhere"),
                "files": .array([.string("x.xml")]),
            ])
        }
    }
}
