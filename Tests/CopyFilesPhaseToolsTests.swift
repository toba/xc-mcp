import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct CopyFilesPhaseToolsTests {
    // MARK: - ListCopyFilesPhases Tests

    @Test
    func `ListCopyFilesPhases tool creation`() {
        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_copy_files_phases")
        #expect(toolDefinition.description == "List all Copy Files build phases for a target")
    }

    @Test
    func `ListCopyFilesPhases with missing parameters`() throws {
        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path/to/project.xcodeproj")])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["target_name": .string("App")])
        }
    }

    @Test
    func `ListCopyFilesPhases with no phases`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No Copy Files build phases found"))
    }

    @Test
    func `ListCopyFilesPhases with existing phases`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a copy files phase manually
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

        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Copy Styles"))
        #expect(message.contains("Resources"))
        #expect(message.contains("styles"))
    }

    @Test
    func `ListCopyFilesPhases with non-existent target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    // MARK: - AddCopyFilesPhase Tests

    @Test
    func `AddCopyFilesPhase tool creation`() {
        let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_copy_files_phase")
        #expect(toolDefinition.description?.contains("Copy Files") == true)
    }

    @Test
    func `AddCopyFilesPhase with missing parameters`() throws {
        let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                "phase_name": .string("Test"),
                // Missing destination
            ])
        }
    }

    @Test
    func `AddCopyFilesPhase creates phase successfully`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
            "subpath": .string("styles"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created"))
        #expect(message.contains("Copy Styles"))

        // Verify the phase was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Styles" }

        #expect(copyPhase != nil)
        #expect(copyPhase?.dstSubfolderSpec == .resources)
        #expect(copyPhase?.dstPath == "styles")
    }

    @Test
    func `AddCopyFilesPhase with invalid destination`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "phase_name": .string("Test"),
                "destination": .string("invalid_destination"),
            ])
        }
    }

    @Test
    func `AddCopyFilesPhase duplicate phase name`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))

        // Add first phase
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        // Try to add duplicate
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("frameworks"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    // MARK: - AddToCopyFilesPhase Tests

    @Test
    func `AddToCopyFilesPhase tool creation`() {
        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_to_copy_files_phase")
        #expect(toolDefinition.description?.contains("Add files") == true)
    }

    @Test
    func `AddToCopyFilesPhase with missing parameters`() throws {
        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                "phase_name": .string("Test"),
                // Missing files
            ])
        }
    }

    @Test
    func `AddToCopyFilesPhase adds files successfully`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create a test file
        let testFilePath = tempDir.appendingPathComponent("style.csl").path
        try "test content".write(toFile: testFilePath, atomically: true, encoding: .utf8)

        // Add the file to project first
        let addFileTool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(testFilePath),
        ])

        // Create copy files phase
        let addPhaseTool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addPhaseTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        // Add file to phase
        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "files": .array([.string(testFilePath)]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Added"))
        #expect(message.contains("style.csl"))

        // Verify file was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let copyPhase = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Styles" }

        #expect(copyPhase?.files?.count == 1)
    }

    @Test
    func `AddToCopyFilesPhase with non-existent phase`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("NonExistent"),
            "files": .array([.string("/some/file.txt")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `AddToCopyFilesPhase with file not in project`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create copy files phase
        let addPhaseTool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addPhaseTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        // Try to add file that's not in project
        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "files": .array([.string("/nonexistent/file.txt")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found in project") || message.contains("Files not found"))
    }

    // MARK: - RemoveCopyFilesPhase Tests

    @Test
    func `RemoveCopyFilesPhase tool creation`() {
        let tool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_copy_files_phase")
        #expect(toolDefinition.description?.contains("Remove") == true)
    }

    @Test
    func `RemoveCopyFilesPhase with missing parameters`() throws {
        let tool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                // Missing phase_name
            ])
        }
    }

    @Test
    func `RemoveCopyFilesPhase removes phase successfully`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create copy files phase
        let addPhaseTool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addPhaseTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
        ])

        // Verify phase exists
        var xcodeproj = try XcodeProj(path: projectPath)
        var target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        var copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
        #expect(copyPhases.contains { $0.name == "Copy Styles" })

        // Remove phase
        let tool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        // Verify phase was removed
        xcodeproj = try XcodeProj(path: projectPath)
        target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        copyPhases = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
        #expect(!copyPhases.contains { $0.name == "Copy Styles" })
    }

    @Test
    func `RemoveCopyFilesPhase with non-existent phase`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("NonExistent"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `RemoveCopyFilesPhase with non-existent target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
            "phase_name": .string("SomePhase"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    // MARK: - Integration Tests

    @Test
    func `Full workflow: create, add files, list, remove`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create test files
        let file1Path = tempDir.appendingPathComponent("style1.csl").path
        let file2Path = tempDir.appendingPathComponent("style2.csl").path
        try "content1".write(toFile: file1Path, atomically: true, encoding: .utf8)
        try "content2".write(toFile: file2Path, atomically: true, encoding: .utf8)

        // Add files to project
        let addFileTool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(file1Path),
        ])
        _ = try addFileTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "file_path": .string(file2Path),
        ])

        // Step 1: Create phase
        let addPhaseTool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let createResult = try addPhaseTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "destination": .string("resources"),
            "subpath": .string("styles"),
        ])
        guard case let .text(createMessage, _, _) = createResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(createMessage.contains("Successfully created"))

        // Step 2: Add files to phase
        let addToTool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let addToResult = try addToTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
            "files": .array([.string(file1Path), .string(file2Path)]),
        ])
        guard case let .text(addToMessage, _, _) = addToResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(addToMessage.contains("Added 2"))

        // Step 3: List phases
        let listTool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let listResult = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage, _, _) = listResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage.contains("Copy Styles"))
        #expect(listMessage.contains("Files: 2"))
        #expect(listMessage.contains("style1.csl"))
        #expect(listMessage.contains("style2.csl"))

        // Step 4: Remove phase
        let removeTool = RemoveCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let removeResult = try removeTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Copy Styles"),
        ])
        guard case let .text(removeMessage, _, _) = removeResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(removeMessage.contains("Successfully removed"))

        // Verify phase is gone
        let finalListResult = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(finalListMessage, _, _) = finalListResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(finalListMessage.contains("No Copy Files build phases found"))
    }

    @Test
    func `AddCopyFilesPhase with all destination types`() throws {
        let destinations = [
            ("resources", PBXCopyFilesBuildPhase.SubFolder.resources),
            ("frameworks", PBXCopyFilesBuildPhase.SubFolder.frameworks),
            ("executables", PBXCopyFilesBuildPhase.SubFolder.executables),
            ("plugins", PBXCopyFilesBuildPhase.SubFolder.plugins),
            ("shared_support", PBXCopyFilesBuildPhase.SubFolder.sharedSupport),
            ("wrapper", PBXCopyFilesBuildPhase.SubFolder.wrapper),
            ("products_directory", PBXCopyFilesBuildPhase.SubFolder.productsDirectory),
        ]

        for (destString, expectedSubfolder) in destinations {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString,
            )
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
            try TestProjectHelper.createTestProjectWithTarget(
                name: "TestProject", targetName: "App", at: projectPath,
            )

            let tool = AddCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
            _ = try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "phase_name": .string("Test Phase"),
                "destination": .string(destString),
            ])

            let xcodeproj = try XcodeProj(path: projectPath)
            let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
            let copyPhase = target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
                .first { $0.name == "Test Phase" }

            #expect(
                copyPhase?.dstSubfolderSpec == expectedSubfolder,
                "Destination '\(destString)' should map to \(expectedSubfolder)",
            )
        }
    }
}
