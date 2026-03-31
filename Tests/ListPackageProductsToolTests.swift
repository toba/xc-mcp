import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListPackageProductsToolTests {
    @Test
    func `Tool creation`() {
        let tool = ListPackageProductsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_package_products")
        #expect(
            toolDefinition.description?
                .contains("List SPM package product dependencies") == true,
        )
    }

    @Test
    func `Empty project`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListPackageProductsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No package product dependencies found"))
    }

    @Test
    func `List products for specific target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a package product
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-http-types.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        let tool = ListPackageProductsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("[App]"))
        #expect(message.contains("HTTPTypes"))
        #expect(message.contains("swift-http-types"))
    }

    @Test
    func `List products for all targets`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a package product to App
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-http-types.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Create second target and add product to it
        let xcodeproj = try XcodeProj(path: projectPath)
        let testTarget = PBXNativeTarget(name: "Tests")
        let frameworksPhase = PBXFrameworksBuildPhase()
        xcodeproj.pbxproj.add(object: frameworksPhase)
        testTarget.buildPhases.append(frameworksPhase)
        xcodeproj.pbxproj.add(object: testTarget)
        if let project = try xcodeproj.pbxproj.rootProject() {
            project.targets.append(testTarget)
        }
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let addProductTool = AddPackageProductTool(
            pathUtility: PathUtility(basePath: tempDir.path),
        )
        _ = try addProductTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Tests"),
            "product_name": Value.string("HTTPTypes"),
        ])

        let tool = ListPackageProductsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("[App]"))
        #expect(message.contains("[Tests]"))
        #expect(message.contains("HTTPTypes"))
    }

    @Test
    func `Target not found`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ListPackageProductsTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistent"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found in project"))
    }
}
