import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

/// Test case for missing parameter validation
struct AddFrameworkMissingParamTestCase: Sendable {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

@Suite("AddFrameworkTool Tests")
struct AddFrameworkToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_framework")
        #expect(toolDefinition.description == "Add framework dependencies")
    }

    static let missingParamCases: [AddFrameworkMissingParamTestCase] = [
        AddFrameworkMissingParamTestCase(
            "Missing project_path",
            [
                "target_name": Value.string("App"),
                "framework_name": Value.string("UIKit"),
            ]
        ),
        AddFrameworkMissingParamTestCase(
            "Missing target_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "framework_name": Value.string("UIKit"),
            ]
        ),
        AddFrameworkMissingParamTestCase(
            "Missing framework_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ]
        ),
    ]

    @Test("Add framework with missing parameter", arguments: missingParamCases)
    func addFrameworkWithMissingParameters(_ testCase: AddFrameworkMissingParamTestCase) throws {
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test("Add system framework")
    func addSystemFramework() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add system framework
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework 'UIKit'"))

        // Verify framework was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let frameworkPhase =
            target?.buildPhases.first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase

        let hasUIKit =
            frameworkPhase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "UIKit.framework"
                }
                return false
            } ?? false

        #expect(hasUIKit == true)
    }

    @Test("Add custom framework without embedding")
    func addCustomFrameworkWithoutEmbedding() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add custom framework
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string(tempDir.appendingPathComponent("Custom.framework").path),
            "embed": Value.bool(false),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(!message.contains("(embedded)"))
    }

    @Test("Add custom framework with embedding")
    func addCustomFrameworkWithEmbedding() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        // Add custom framework with embedding
        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string(tempDir.appendingPathComponent("Custom.framework").path),
            "embed": Value.bool(true),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added framework"))
        #expect(message.contains("(embedded)"))

        // Verify embed frameworks phase was created
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }

        let hasEmbedPhase =
            target?.buildPhases.contains { phase in
                if let copyPhase = phase as? PBXCopyFilesBuildPhase {
                    return copyPhase.dstSubfolderSpec == .frameworks
                }
                return false
            } ?? false

        #expect(hasEmbedPhase == true)
    }

    @Test("Add duplicate framework")
    func addDuplicateFramework() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath)

        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ]

        // Add framework first time
        _ = try tool.execute(arguments: args)

        // Try to add again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Add framework to non-existent target")
    func addFrameworkToNonExistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "framework_name": Value.string("UIKit"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}
