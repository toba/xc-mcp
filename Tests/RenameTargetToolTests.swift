import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
@testable import XCMCPTools
import XcodeProj

@Suite("RenameTargetTool Tests")
struct RenameTargetToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "rename_target")
        #expect(toolDefinition.description == "Rename an existing target in-place, updating all references")
    }

    @Test("Rename target with missing parameters")
    func renameTargetWithMissingParameters() throws {
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "new_name": Value.string("NewApp"),
            ])
        }

        // Missing target_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_name": Value.string("NewApp"),
            ])
        }

        // Missing new_name
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }
    }

    @Test("Rename existing target")
    func renameExistingTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed target 'App' to 'NewApp'"))

        // Verify target was renamed
        let xcodeproj = try XcodeProj(path: projectPath)
        let renamedTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
        #expect(renamedTarget != nil)

        // Verify old name is gone
        let oldTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(oldTarget == nil)

        // Verify PRODUCT_NAME updated
        let buildConfig = renamedTarget?.buildConfigurationList?.buildConfigurations.first
        #expect(buildConfig?.buildSettings["PRODUCT_NAME"]?.stringValue == "NewApp")

        // Verify BUNDLE_IDENTIFIER preserved (not changed)
        #expect(
            buildConfig?.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.example.App"
        )
    }

    @Test("Rename non-existent target")
    func renameNonExistentTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "new_name": Value.string("NewTarget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Rename to existing target name")
    func renameToExistingTargetName() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add another target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("ExistingTarget"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.existing"),
        ])

        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("ExistingTarget"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Rename target with dependencies")
    func renameTargetWithDependencies() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ])

        // Add dependency: App depends on Framework
        let addDependencyTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addDependencyTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ])

        // Rename the framework target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "new_name": Value.string("CoreLib"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify dependency reference was updated
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let hasDependency = appTarget?.dependencies.contains { $0.name == "CoreLib" } ?? false
        #expect(hasDependency == true)
    }

    @Test("Rename target with product reference")
    func renameTargetWithProductReference() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Add a product reference to the target
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let productRef = PBXFileReference(
            sourceTree: .buildProductsDir, name: "App.app", path: "App.app"
        )
        xcodeproj.pbxproj.add(object: productRef)
        target.product = productRef
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Rename the target
        let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "new_name": Value.string("NewApp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed"))

        // Verify product reference path was updated
        let updatedProj = try XcodeProj(path: projectPath)
        let renamedTarget = updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
        #expect(renamedTarget?.product?.path == "NewApp.app")
    }
}
