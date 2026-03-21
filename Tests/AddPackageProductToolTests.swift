import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct AddPackageProductToolTests {
    @Test
    func `tool creation`() {
        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_package_product")
        #expect(toolDefinition.description?
            .contains("Link an existing Swift Package product") == true)
    }

    @Test
    func `missing parameters`() {
        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: "/tmp"))

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
    func `add product to target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a second target
        let xcodeproj = try XcodeProj(path: projectPath)
        let testTarget = PBXNativeTarget(name: "Tests")
        xcodeproj.pbxproj.add(object: testTarget)
        if let project = try xcodeproj.pbxproj.rootProject() {
            project.targets.append(testTarget)
        }

        // Add a remote package with a product linked to App
        let packageRef = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/apple/swift-http-types.git",
            versionRequirement: .upToNextMajorVersion("1.0.0"),
        )
        xcodeproj.pbxproj.add(object: packageRef)
        if let project = try xcodeproj.pbxproj.rootProject() {
            project.remotePackages.append(packageRef)
        }

        let appTarget = try #require(xcodeproj.pbxproj.nativeTargets.first(where: {
            $0.name == "App"
        }))
        let productDep = XCSwiftPackageProductDependency(
            productName: "HTTPTypes",
            package: packageRef,
        )
        xcodeproj.pbxproj.add(object: productDep)
        appTarget.packageProductDependencies = [productDep]

        try xcodeproj.write(path: projectPath)

        // Now use the tool to add HTTPTypes to the Tests target
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Tests"),
            "product_name": Value.string("HTTPTypes"),
        ])

        if case let .text(content) = result.content[0] {
            #expect(content.contains("Linked product 'HTTPTypes' to target 'Tests'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify the product was added
        let reloaded = try XcodeProj(path: projectPath)
        let reloadedTests = try #require(reloaded.pbxproj.nativeTargets.first(where: {
            $0.name == "Tests"
        }))
        #expect(reloadedTests.packageProductDependencies?.count == 1)
        #expect(reloadedTests.packageProductDependencies?.first?.productName == "HTTPTypes")
    }

    @Test
    func `duplicate product rejected`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a product already linked to App
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first)
        let productDep = XCSwiftPackageProductDependency(
            productName: "Alamofire",
            package: nil,
        )
        xcodeproj.pbxproj.add(object: productDep)
        target.packageProductDependencies = [productDep]
        try xcodeproj.write(path: projectPath)

        // Try to add the same product again
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "target_name": Value.string("App"),
                "product_name": Value.string("Alamofire"),
            ])
        }
    }

    @Test
    func `target not found`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = AddPackageProductTool(pathUtility: PathUtility(basePath: tempDir.path))
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "target_name": Value.string("NonExistent"),
                "product_name": Value.string("HTTPTypes"),
            ])
        }
    }
}
