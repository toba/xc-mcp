import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SetProductNameToolTests {
    @Test
    func `Tool creation`() {
        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_product_name")
        #expect(toolDefinition.description?.contains("PRODUCT_NAME") == true)
    }

    @Test
    func `Missing required params throws`() {
        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "product_name": Value.string("jig"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ])
        }
    }

    @Test
    func `A product name holding a path separator throws`() {
        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "product_name": Value.string("Build/jig"),
            ])
        }
    }

    /// Creates a project with one target whose product reference carries `productPath`.
    private func makeProject(
        at dir: URL,
        targetName: String = "JigTool",
        productPath: String?,
        productType: PBXProductType = .commandLineTool,
    ) throws -> Path {
        let projectPath = Path(dir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: targetName, at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == targetName })
        target.productType = productType

        if let productPath {
            let productRef = PBXFileReference(sourceTree: .buildProductsDir, path: productPath)
            xcodeproj.pbxproj.add(object: productRef)
            target.product = productRef
        }

        try PBXProjWriter.write(xcodeproj, to: projectPath)
        return projectPath
    }

    @Test
    func `Set product name writes every configuration and the product path`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir, productPath: "JigTool")

        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("JigTool"),
            "product_name": Value.string("jig"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("PRODUCT_NAME"))
        #expect(message.contains("product path"))

        let updated = try XcodeProj(path: projectPath)
        let target = try #require(updated.pbxproj.nativeTargets.first { $0.name == "JigTool" })

        // The target name stays put. Only the product it builds is renamed.
        #expect(target.product?.path == "jig")

        // The target's own productName field means the target name to every other tool, so this
        // tool leaves it alone.
        #expect(target.productName == nil)

        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            #expect(config.buildSettings["PRODUCT_NAME"]?.stringValue == "jig")
        }
    }

    @Test
    func `Set product name keeps the product extension`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(
            at: tempDir, targetName: "AppTarget", productPath: "AppTarget.app",
            productType: .application,
        )

        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTarget"),
            "product_name": Value.string("Jig"),
        ])

        let updated = try XcodeProj(path: projectPath)
        let target = try #require(updated.pbxproj.nativeTargets.first { $0.name == "AppTarget" })
        #expect(target.product?.path == "Jig.app")
    }

    @Test
    func `Set product name reports a target with no product reference`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir, productPath: nil)

        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("JigTool"),
            "product_name": Value.string("jig"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("no product file reference"))

        let updated = try XcodeProj(path: projectPath)
        let target = try #require(updated.pbxproj.nativeTargets.first { $0.name == "JigTool" })
        let config = try #require(target.buildConfigurationList?.buildConfigurations.first)
        #expect(config.buildSettings["PRODUCT_NAME"]?.stringValue == "jig")
    }

    @Test
    func `Set product name is idempotent`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir, productPath: "JigTool")

        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("JigTool"),
            "product_name": Value.string("jig"),
        ]
        _ = try tool.execute(arguments: args)
        let second = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = second.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No changes made"))
    }

    @Test
    func `Set product name reports an unknown target`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir, productPath: "JigTool")

        let tool = SetProductNameTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Missing"),
            "product_name": Value.string("jig"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}
