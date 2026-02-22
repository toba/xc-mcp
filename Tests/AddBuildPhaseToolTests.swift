import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

/// Test case for missing parameter validation
struct AddBuildPhaseMissingParamTestCase: Sendable {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

@Suite("AddBuildPhaseTool Tests")
struct AddBuildPhaseToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_build_phase")
        #expect(toolDefinition.description == "Add custom build phases")
    }

    static let missingParamCases: [AddBuildPhaseMissingParamTestCase] = [
        AddBuildPhaseMissingParamTestCase(
            "Missing project_path",
            [
                "target_name": Value.string("App"),
                "phase_name": Value.string("Custom Script"),
                "phase_type": Value.string("run_script"),
            ]
        ),
        AddBuildPhaseMissingParamTestCase(
            "Missing target_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "phase_name": Value.string("Custom Script"),
                "phase_type": Value.string("run_script"),
            ]
        ),
        AddBuildPhaseMissingParamTestCase(
            "Missing phase_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "phase_type": Value.string("run_script"),
            ]
        ),
        AddBuildPhaseMissingParamTestCase(
            "Missing phase_type",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "phase_name": Value.string("Custom Script"),
            ]
        ),
    ]

    @Test("Add build phase with missing parameter", arguments: missingParamCases)
    func addBuildPhaseWithMissingParameters(_ testCase: AddBuildPhaseMissingParamTestCase) throws {
        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test("Add run script build phase")
    func addRunScriptBuildPhase() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add run script phase
        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("SwiftLint"),
            "phase_type": Value.string("run_script"),
            "script": Value.string(
                "if which swiftlint >/dev/null; then\n  swiftlint\nelse\n  echo \"warning: SwiftLint not installed\"\nfi"
            ),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added run_script build phase 'SwiftLint'"))

        // Verify script phase was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }

        let hasScriptPhase =
            target?.buildPhases.contains { phase in
                if let scriptPhase = phase as? PBXShellScriptBuildPhase {
                    return scriptPhase.name == "SwiftLint"
                }
                return false
            } ?? false

        #expect(hasScriptPhase == true)
    }

    @Test("Add copy files build phase")
    func addCopyFilesBuildPhase() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add a file to the project first
        let addFileTool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let testFilePath = tempDir.appendingPathComponent("config.plist").path
        try "<plist></plist>".write(toFile: testFilePath, atomically: true, encoding: .utf8)

        _ = try addFileTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(testFilePath),
        ])

        // Add copy files phase
        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Copy Config Files"),
            "phase_type": Value.string("copy_files"),
            "destination": Value.string("resources"),
            "files": .array([Value.string(testFilePath)]),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added copy_files build phase"))

        // Verify copy files phase was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }

        let hasCopyPhase =
            target?.buildPhases.contains { phase in
                if let copyPhase = phase as? PBXCopyFilesBuildPhase {
                    return copyPhase.name == "Copy Config Files"
                        && copyPhase.dstSubfolderSpec == .resources
                }
                return false
            } ?? false

        #expect(hasCopyPhase == true)
    }

    @Test("Add run script phase without script")
    func addRunScriptPhaseWithoutScript() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Script"),
            "phase_type": Value.string("run_script"),
            // Missing script parameter
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test("Add copy files phase without destination")
    func addCopyFilesPhaseWithoutDestination() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Copy Files"),
            "phase_type": Value.string("copy_files"),
            // Missing destination parameter
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test("Add build phase with invalid phase type")
    func addBuildPhaseWithInvalidPhaseType() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Invalid Phase"),
            "phase_type": Value.string("invalid_type"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test("Add build phase to non-existent target")
    func addBuildPhaseToNonExistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddBuildPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "phase_name": Value.string("Script"),
            "phase_type": Value.string("run_script"),
            "script": Value.string("echo Hello"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Copy files phase dstSubfolderSpec is preserved after other operations")
    func copyFilesPhasePreservedAfterOtherOperations() throws {
        // This test verifies the fix for bug xc-mcp-f1y3:
        // "MCP tools corrupt unrelated PBXCopyFilesBuildPhase sections"

        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target and add a copy files build phase
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add a copy files build phase with dstSubfolderSpec = .resources
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "styles",
            dstSubfolderSpec: .resources,
            name: "Copy Styles"
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Verify the phase was created correctly
        let verifyProject = try XcodeProj(path: projectPath)
        let verifyTarget = try #require(
            verifyProject.pbxproj.nativeTargets.first { $0.name == "App" })
        let verifyCopyPhase = verifyTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Styles" }

        #expect(verifyCopyPhase != nil, "Copy phase should exist")
        #expect(
            verifyCopyPhase?.dstSubfolderSpec == .resources,
            "dstSubfolderSpec should be .resources before modification"
        )

        // Now use add_synchronized_folder to add a folder (this was corrupting copy phases)
        let folderPath = Path(tempDir.path) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true
        )

        let folderTool = AddFolderTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try folderTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(folderPath.string),
        ])

        // Verify the copy files phase still has the correct dstSubfolderSpec
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(
            updatedProject.pbxproj.nativeTargets.first { $0.name == "App" })
        let updatedCopyPhase = updatedTarget.buildPhases.compactMap {
            $0 as? PBXCopyFilesBuildPhase
        }
        .first { $0.name == "Copy Styles" }

        #expect(updatedCopyPhase != nil, "Copy phase should still exist after folder operation")
        #expect(
            updatedCopyPhase?.dstSubfolderSpec == .resources,
            "dstSubfolderSpec should remain .resources after folder operation (was corrupted to \(String(describing: updatedCopyPhase?.dstSubfolderSpec)))"
        )
        #expect(
            updatedCopyPhase?.dstPath == "styles",
            "dstPath should remain 'styles' after folder operation"
        )
    }
}
