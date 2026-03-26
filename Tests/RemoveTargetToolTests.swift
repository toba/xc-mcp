import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveTargetToolTests {
    @Test
    func `Tool creation`() {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_target")
        #expect(toolDefinition.description == "Remove an existing target")
    }

    @Test
    func `Remove target with missing project path`() throws {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["target_name": Value.string("TestTarget")])
        }
    }

    @Test
    func `Remove target with missing target name`() throws {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: ["project_path": Value.string("/path/to/project.xcodeproj")],
            )
        }
    }

    @Test
    func `Remove existing target`() throws {
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

        // Verify target exists
        var xcodeproj = try XcodeProj(path: projectPath)
        let targetExists = xcodeproj.pbxproj.nativeTargets.contains { $0.name == "TestApp" }
        #expect(targetExists == true)

        // Remove the target
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestApp"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'TestApp'"))

        // Verify target was removed
        xcodeproj = try XcodeProj(path: projectPath)
        let targetStillExists = xcodeproj.pbxproj.nativeTargets.contains { $0.name == "TestApp" }
        #expect(targetStillExists == false)
    }

    @Test
    func `Remove non-existent target`() throws {
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

        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `Remove target with dependencies`() throws {
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
            name: "TestProject", targetName: "MainApp", at: projectPath,
        )

        // Add another target
        let addTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Remove the framework target
        let removeTool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let removeArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
        ]

        let result = try removeTool.execute(arguments: removeArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'Framework'"))

        // Verify only the framework target was removed
        let xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.count == 1)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.name == "MainApp")
    }

    @Test
    func `Remove target cleans up dependency and proxy objects`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a project with two targets where AppTarget depends on LibTarget
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "LibTarget", at: projectPath,
        )

        // Wire up a real dependency: AppTarget depends on LibTarget
        var xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = try #require(xcodeproj.pbxproj.nativeTargets
            .first { $0.name == "AppTarget" })
        let libTarget = try #require(xcodeproj.pbxproj.nativeTargets
            .first { $0.name == "LibTarget" })

        let proxy = try PBXContainerItemProxy(
            containerPortal: .project(#require(xcodeproj.pbxproj.rootObject)),
            remoteGlobalID: .object(libTarget),
            proxyType: .nativeTarget,
            remoteInfo: "LibTarget",
        )
        xcodeproj.pbxproj.add(object: proxy)

        let dependency = PBXTargetDependency(
            name: "LibTarget",
            target: libTarget,
            targetProxy: proxy,
        )
        xcodeproj.pbxproj.add(object: dependency)
        appTarget.dependencies.append(dependency)

        try xcodeproj.write(path: projectPath)

        // Verify the dependency objects exist
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.targetDependencies.count == 1)
        #expect(xcodeproj.pbxproj.containerItemProxies.count == 1)

        // Remove LibTarget
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("LibTarget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'LibTarget'"))

        // Verify orphaned objects were cleaned up
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.count == 1)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.name == "AppTarget")
        #expect(xcodeproj.pbxproj.targetDependencies.isEmpty)
        #expect(xcodeproj.pbxproj.containerItemProxies.isEmpty)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.dependencies.isEmpty == true)
    }
}
