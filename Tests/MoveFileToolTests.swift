import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for missing parameter validation
struct MoveFileMissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct MoveFileToolTests {
    @Test
    func `Tool creation`() {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "move_file")
        #expect(toolDefinition.description == "Move or rename a file within the project")
    }

    static let missingParamCases: [MoveFileMissingParamTestCase] = [
        MoveFileMissingParamTestCase(
            "Missing project_path",
            [
                "old_path": Value.string("old.swift"),
                "new_path": Value.string("new.swift"),
            ],
        ),
        MoveFileMissingParamTestCase(
            "Missing old_path",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_path": Value.string("new.swift"),
            ],
        ),
        MoveFileMissingParamTestCase(
            "Missing new_path",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "old_path": Value.string("old.swift"),
            ],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Move file with missing parameter`(_ testCase: MoveFileMissingParamTestCase) throws {
        let tool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test
    func `Move file in project`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        // First add a file to move
        let addTool = AddFileTool(pathUtility: PathUtility(basePath: "/"))
        let oldFilePath = tempDir.appendingPathComponent("OldFile.swift").path
        try "// Test file".write(toFile: oldFilePath, atomically: true, encoding: .utf8)

        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(oldFilePath),
            "target_name": Value.string("TestApp"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Now move the file
        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let newFilePath = tempDir.appendingPathComponent("NewFile.swift").path
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string(oldFilePath),
            "new_path": Value.string(newFilePath),
            "move_on_disk": Value.bool(false),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully moved"))

        // Verify file was moved in project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences

        // Check that old path doesn't exist
        let oldFileExists = fileReferences.contains {
            $0.path == oldFilePath || $0.name == "OldFile.swift"
        }
        #expect(oldFileExists == false)

        // Check that new path exists
        let newFileExists = fileReferences.contains {
            $0.path == newFilePath || $0.name == "NewFile.swift"
        }
        #expect(newFileExists == true)

        // Verify file still exists at old path on disk (move_on_disk was false)
        #expect(FileManager.default.fileExists(atPath: oldFilePath) == true)
        #expect(FileManager.default.fileExists(atPath: newFilePath) == false)
    }

    @Test
    func `Move file on disk`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        // First add a file to move
        let addTool = AddFileTool(pathUtility: PathUtility(basePath: "/"))
        let oldFilePath = tempDir.appendingPathComponent("OldFile.swift").path
        try "// Test file".write(toFile: oldFilePath, atomically: true, encoding: .utf8)

        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(oldFilePath),
            "target_name": Value.string("TestApp"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Now move the file with move_on_disk = true
        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let newFilePath = tempDir.appendingPathComponent("subfolder/NewFile.swift").path
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string(oldFilePath),
            "new_path": Value.string(newFilePath),
            "move_on_disk": Value.bool(true),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully moved"))

        // Verify file was moved on disk
        #expect(FileManager.default.fileExists(atPath: oldFilePath) == false)
        #expect(FileManager.default.fileExists(atPath: newFilePath) == true)

        // Verify content is preserved
        let content = try String(contentsOfFile: newFilePath, encoding: .utf8)
        #expect(content == "// Test file")
    }

    @Test
    func `Move file in synchronized folder exception set`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithSyncFolder(
            name: "TestProject",
            targetName: "TestApp",
            folderPath: "TestSupport",
            membershipExceptions: [
                "Snapshots/Conformances/NSViewController.swift",
            ],
            at: projectPath,
        )

        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string(
                "Snapshots/Conformances/NSViewController.swift",
            ),
            "new_path": Value.string(
                "Snapshots/Conformances/NSViewController+snapshot.swift",
            ),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully moved"))
        #expect(message.contains("synchronized folder exception"))

        // Verify the exception set was updated
        let xcodeproj = try XcodeProj(path: projectPath)
        let exceptionSets = xcodeproj.pbxproj
            .fileSystemSynchronizedBuildFileExceptionSets
        #expect(exceptionSets.count == 1)
        let exceptions = exceptionSets[0].membershipExceptions ?? []
        #expect(exceptions.contains("Snapshots/Conformances/NSViewController+snapshot.swift"))
        #expect(!exceptions.contains("Snapshots/Conformances/NSViewController.swift"))
    }

    @Test
    func `Move non-existent file`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let moveTool = MoveFileTool(pathUtility: PathUtility(basePath: "/"))
        let moveArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "old_path": Value.string("/path/to/nonexistent.swift"),
            "new_path": Value.string("/path/to/new.swift"),
            "move_on_disk": Value.bool(false),
        ]

        let result = try moveTool.execute(arguments: moveArgs)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("File not found"))
    }
}
