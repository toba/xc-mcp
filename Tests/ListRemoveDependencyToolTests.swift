import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListRemoveDependencyToolTests {
    private func makeProjectWithDependency() throws -> (Path, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTargetTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("Framework"),
            "product_type": .string("framework"),
            "bundle_identifier": .string("com.test.framework"),
        ])

        let addDep = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addDep.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Framework"),
        ])

        return (projectPath, tempDir)
    }

    @Test
    func `list_dependencies tool metadata`() {
        let tool = ListDependenciesTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "list_dependencies")
    }

    @Test
    func `remove_dependency tool metadata`() {
        let tool = RemoveDependencyTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "remove_dependency")
    }

    @Test
    func `list_dependencies reports edges added by add_dependency`() throws {
        let (projectPath, tempDir) = try makeProjectWithDependency()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let list = ListDependenciesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try list.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Framework"))
        #expect(message.contains("proxyType=nativeTarget"))
        #expect(message.contains("remoteInfo=Framework"))
    }

    @Test
    func `list_dependencies on target with no deps`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let list = ListDependenciesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try list.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("no PBXTargetDependency"))
    }

    @Test
    func `list_dependencies on missing target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let list = ListDependenciesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try list.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("Nope"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `remove_dependency drops the PBXTargetDependency and its proxy`() throws {
        let (projectPath, tempDir) = try makeProjectWithDependency()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Snapshot pre-state.
        let before = try XcodeProj(path: projectPath)
        let beforeProxyCount = before.pbxproj.containerItemProxies.count
        let beforeDepCount = before.pbxproj.targetDependencies.count
        #expect(beforeProxyCount >= 1)
        #expect(beforeDepCount >= 1)

        let remove = RemoveDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try remove.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Framework"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        let after = try XcodeProj(path: projectPath)
        let appTarget = after.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(appTarget?.dependencies.isEmpty == true)
        #expect(after.pbxproj.containerItemProxies.count == beforeProxyCount - 1)
        #expect(after.pbxproj.targetDependencies.count == beforeDepCount - 1)

        // Framework target itself must survive.
        #expect(after.pbxproj.nativeTargets.contains { $0.name == "Framework" })
    }

    @Test
    func `remove_dependency on missing edge is a no-op message`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let remove = RemoveDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try remove.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Ghost"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("no PBXTargetDependency edge"))
    }

    @Test
    func `add_dependency round-trips through remove_dependency`() throws {
        let (projectPath, tempDir) = try makeProjectWithDependency()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let remove = RemoveDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try remove.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Framework"),
        ])

        let addDep = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let readded = try addDep.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "dependency_name": .string("Framework"),
        ])
        guard case let .text(message, _, _) = readded.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added dependency"))
    }
}
