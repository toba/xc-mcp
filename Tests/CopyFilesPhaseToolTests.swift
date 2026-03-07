import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AddCopyFilesPhaseTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("AddCopyFilesPhaseTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_copy_files_phase")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["target_name"] != nil)
                #expect(props["phase_name"] != nil)
                #expect(props["destination"] != nil)
                #expect(props["subpath"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 4)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("target_name")))
                #expect(required.contains(.string("phase_name")))
                #expect(required.contains(.string("destination")))
            }
        }
    }

    @Test
    func `Validates required parameters`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "target_name": .string("App"),
                "phase_name": .string("Copy Styles"),
            ])
        }
    }

    @Test
    func `Creates copy files phase with destination`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully created Copy Files phase"))
            #expect(message.contains("Copy Styles"))
            #expect(message.contains("resources"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the phase was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
        let phase = copyPhases.first { $0.name == "Copy Styles" }
        #expect(phase != nil)
        #expect(phase?.dstSubfolderSpec == .resources)
    }

    @Test
    func `Creates copy files phase with subpath`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Plugins"),
            "destination": .string("plugins"),
            "subpath": .string("Extensions"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Subpath: Extensions"))
        } else {
            Issue.record("Expected text result")
        }

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Plugins" }
        #expect(phase?.dstSubfolderSpec == .plugins)
        #expect(phase?.dstPath == "Extensions")
    }

    @Test
    func `Idempotent when phase already exists`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create the phase first time
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        // Try to create again
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("already exists"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Fails with invalid destination`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "phase_name": .string("Copy Styles"),
                "destination": .string("invalid_dest"),
            ])
        }
    }

    @Test
    func `Reports target not found`() throws {
        let tool = AddCopyFilesPhase(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }
}

struct ListCopyFilesPhasesTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("ListCopyFilesPhasesTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `tool properties`() {
        let tool = ListCopyFilesPhases(pathUtility: pathUtility)

        #expect(tool.tool().name == "list_copy_files_phases")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 2)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("target_name")))
            }
        }
    }

    @Test
    func `validate required parameters`() throws {
        let tool = ListCopyFilesPhases(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
            ])
        }
    }

    @Test
    func `Lists copy files phases`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a copy files phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "styles",
            dstSubfolderSpec: .resources,
            name: "Copy Styles",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = ListCopyFilesPhases(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Copy Styles"))
            #expect(message.contains("Resources"))
            #expect(message.contains("Subpath: styles"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Reports no phases found`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListCopyFilesPhases(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("No Copy Files build phases found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `reports target not found`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListCopyFilesPhases(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }
}

struct AddToCopyFilesPhaseTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("AddToCopyFilesPhaseTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func toolProperties() {
        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_to_copy_files_phase")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["target_name"] != nil)
                #expect(props["phase_name"] != nil)
                #expect(props["files"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 4)
            }
        }
    }

    @Test
    func validateRequiredParameters() throws {
        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "target_name": .string("App"),
                "phase_name": .string("Copy Styles"),
            ])
        }
    }

    @Test
    func `Adds file to copy files phase`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a file to the project
        let testFilePath = Path(tempDir) + "config.plist"
        try "<plist></plist>".write(
            toFile: testFilePath.string, atomically: true, encoding: .utf8,
        )

        let addFileTool = AddFileTool(pathUtility: pathUtility)
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(testFilePath.string),
        ])

        // Add a copy files phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .resources,
            name: "Copy Configs",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Add the file to the phase
        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Configs"),
            "files": .array([.string(testFilePath.string)]),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Added"))
            #expect(message.contains("config.plist"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the file was added
        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let updatedPhase = updatedTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Configs" }
        #expect(updatedPhase?.files?.count == 1)
    }

    @Test
    func `Reports phase not found`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("NonExistent"),
            "files": .array([.string("file.swift")]),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Applies explicit attributes to build file`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework file to the project
        let fwPath = Path(tempDir) + "MyLib.framework"
        try FileManager.default.createDirectory(
            atPath: fwPath.string, withIntermediateDirectories: true,
        )

        let addFileTool = AddFileTool(pathUtility: pathUtility)
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(fwPath.string),
        ])

        // Add an Embed Frameworks copy files phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Add file with explicit attributes
        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Embed Frameworks"),
            "files": .array([.string(fwPath.string)]),
            "attributes": .array([.string("CodeSignOnCopy")]),
        ])

        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let updatedPhase = updatedTarget.buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Embed Frameworks" }
        let buildFile = try #require(updatedPhase?.files?.first)
        #expect(buildFile.attributes == ["CodeSignOnCopy"])
    }

    @Test
    func `Auto-defaults attributes for Embed Frameworks phase`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let fwPath = Path(tempDir) + "Other.framework"
        try FileManager.default.createDirectory(
            atPath: fwPath.string, withIntermediateDirectories: true,
        )

        let addFileTool = AddFileTool(pathUtility: pathUtility)
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(fwPath.string),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Add file WITHOUT explicit attributes — should auto-default
        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Embed Frameworks"),
            "files": .array([.string(fwPath.string)]),
        ])

        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let updatedPhase = updatedTarget.buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Embed Frameworks" }
        let buildFile = try #require(updatedPhase?.files?.first)
        #expect(buildFile.attributes == ["CodeSignOnCopy", "RemoveHeadersOnCopy"])
    }

    @Test
    func `Reports files not found in project`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a copy files phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .resources,
            name: "Copy Configs",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = AddToCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Configs"),
            "files": .array([.string("nonexistent.plist")]),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found in project"))
        } else {
            Issue.record("Expected text result")
        }
    }
}

struct RemoveCopyFilesPhaseTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("RemoveCopyFilesPhaseTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func toolProperties() {
        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)

        #expect(tool.tool().name == "remove_copy_files_phase")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("target_name")))
                #expect(required.contains(.string("phase_name")))
            }
        }
    }

    @Test
    func validateRequiredParameters() throws {
        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "target_name": .string("App"),
            ])
        }
    }

    @Test
    func `Removes copy files phase`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a copy files phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .resources,
            name: "Copy Styles",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully removed"))
            #expect(message.contains("Copy Styles"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the phase was removed
        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhases = updatedTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .filter { $0.name == "Copy Styles" }
        #expect(copyPhases.isEmpty)
    }

    @Test
    func `reports phase not found`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("NonExistent"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func reportsTargetNotFound() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
            "phase_name": .string("Copy Styles"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Removes phase with build files`() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a file to the project
        let testFilePath = Path(tempDir) + "config.plist"
        try "<plist></plist>".write(
            toFile: testFilePath.string, atomically: true, encoding: .utf8,
        )

        let addFileTool = AddFileTool(pathUtility: pathUtility)
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(testFilePath.string),
        ])

        // Add a copy files phase with a build file
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let fileRef = try #require(
            xcodeproj.pbxproj.fileReferences.first { $0.path == "config.plist" },
        )
        let buildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile)

        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .resources,
            name: "Copy Configs",
            buildActionMask: PBXBuildPhase.defaultBuildActionMask,
            files: [buildFile],
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Remove the phase
        let tool = RemoveCopyFilesPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Configs"),
        ])

        if case let .text(message) = result.content.first {
            #expect(message.contains("Successfully removed"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the phase and build files were removed
        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhases = updatedTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .filter { $0.name == "Copy Configs" }
        #expect(copyPhases.isEmpty)
    }
}
