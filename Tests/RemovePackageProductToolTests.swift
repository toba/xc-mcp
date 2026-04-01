import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemovePackageProductToolTests {
    @Test
    func `Tool creation`() {
        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_package_product")
        #expect(
            toolDefinition.description?
                .contains("Remove an SPM package product") == true,
        )
    }

    @Test
    func `Missing parameters`() {
        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/tmp/test.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/tmp/test.xcodeproj"),
                "product_name": Value.string("HTTPTypes"),
            ])
        }
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

        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistent"),
            "product_name": Value.string("HTTPTypes"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found in project"))
    }

    @Test
    func `Product not found on target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found in target"))
    }

    @Test
    func `Remove product from target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a package with a product linked to App
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-http-types.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Verify setup
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(target.packageProductDependencies?.count == 1)

        let frameworksPhase = target.buildPhases
            .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
        let buildFilesBefore = frameworksPhase?.files?.filter { $0.product != nil } ?? []
        #expect(buildFilesBefore.count == 1)

        // Remove the product
        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Removed product 'HTTPTypes' from target 'App'"))

        // Verify product dependency and build file were removed
        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(updatedTarget.packageProductDependencies?.isEmpty == true)

        let updatedPhase = updatedTarget.buildPhases
            .first { $0 is PBXFrameworksBuildPhase } as? PBXFrameworksBuildPhase
        let buildFilesAfter = updatedPhase?.files?.filter { $0.product != nil } ?? []
        #expect(buildFilesAfter.isEmpty)

        // Verify the package itself is still in the project
        let project = try updated.pbxproj.rootProject()
        #expect(project?.remotePackages.count == 1)
    }

    @Test
    func `Remove product cleans up PBXTargetDependency with productRef`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a package with a product linked to App
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-http-types.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Simulate what Xcode GUI does: add a PBXTargetDependency with productRef
        // pointing to the XCSwiftPackageProductDependency
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let productDep = try #require(target.packageProductDependencies?.first)

        let targetDependency = PBXTargetDependency(
            name: productDep.productName,
            product: productDep,
        )
        xcodeproj.pbxproj.add(object: targetDependency)
        target.dependencies.append(targetDependency)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        // Verify PBXTargetDependency exists before removal
        let before = try XcodeProj(path: projectPath)
        let targetBefore = try #require(before.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(targetBefore.dependencies.count == 1)
        #expect(targetBefore.dependencies.first?.product != nil)

        // Remove the product
        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Removed product 'HTTPTypes' from target 'App'"))

        // Verify both packageProductDependencies AND PBXTargetDependency were cleaned up
        let after = try XcodeProj(path: projectPath)
        let targetAfter = try #require(after.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(targetAfter.packageProductDependencies?.isEmpty == true)
        #expect(targetAfter.dependencies.isEmpty)

        // Verify no dangling references in the raw pbxproj file:
        // the deleted PBXTargetDependency's UUID should not appear
        let pbxprojPath = projectPath + "project.pbxproj"
        let rawContents = try String(
            contentsOf: URL(fileURLWithPath: pbxprojPath.string),
            encoding: .utf8,
        )
        #expect(!rawContents.contains("PBXTargetDependency"))
    }

    @Test
    func `Remove product from one target leaves other target intact`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a package to App
        let addTool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "package_url": Value.string("https://github.com/apple/swift-http-types.git"),
            "requirement": Value.string("1.0.0"),
            "target_name": Value.string("App"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Add the same product to a second target
        let addProductTool = AddPackageProductTool(
            pathUtility: PathUtility(basePath: tempDir.path),
        )

        // Create second target first
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

        _ = try addProductTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Tests"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Verify both targets have the product
        let before = try XcodeProj(path: projectPath)
        let appBefore = try #require(before.pbxproj.nativeTargets.first { $0.name == "App" })
        let testsBefore = try #require(before.pbxproj.nativeTargets.first { $0.name == "Tests" })
        #expect(appBefore.packageProductDependencies?.count == 1)
        #expect(testsBefore.packageProductDependencies?.count == 1)

        // Remove product from Tests only
        let tool = RemovePackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Tests"),
            "product_name": Value.string("HTTPTypes"),
        ])

        // Verify Tests lost the product but App still has it
        let after = try XcodeProj(path: projectPath)
        let appAfter = try #require(after.pbxproj.nativeTargets.first { $0.name == "App" })
        let testsAfter = try #require(after.pbxproj.nativeTargets.first { $0.name == "Tests" })
        #expect(appAfter.packageProductDependencies?.count == 1)
        #expect(testsAfter.packageProductDependencies?.isEmpty == true)
    }
}
