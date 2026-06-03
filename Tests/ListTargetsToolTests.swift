import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListTargetsToolTests {
    @Test func `list targets tool creation`() {
        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_targets")
        #expect(toolDefinition.description?.contains("List all targets in an Xcode project") == true)
    }

    @Test func `list targets with missing project path`() throws {
        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test func `list targets with invalid project path`() throws {
        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: "/tmp"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func `list targets filter by product type`() throws {
        let (tool, projectPath) = try makeTwoTargetTool(
            target1: "AppA", target2: "AppB",
        )
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "product_type": .string("com.apple.product-type.application"),
        ])
        let text = textContent(result)
        #expect(text.contains("AppA"))
        #expect(text.contains("AppB"))
        #expect(text.contains("2 matches"))
    }

    @Test func `list targets filter excludes by product type`() throws {
        let (tool, projectPath) = try makeTwoTargetTool(
            target1: "AppA", target2: "AppB",
        )
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "product_type": .string("com.apple.product-type.framework"),
        ])
        let text = textContent(result)
        #expect(text.contains("0 matches"))
        #expect(text.contains("(no matches)"))
    }

    @Test func `list targets has dependency and missing dependency`() throws {
        // Create project with AppA depending on AppB
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TwoTargets.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TwoTargets", target1: "AppA", target2: "AppB", at: projectPath,
        )
        // Add AppA -> AppB dependency
        let xcodeproj = try XcodeProj(path: projectPath)
        let appA = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppA" }!
        let appB = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppB" }!
        _ = try appA.addDependency(target: appB)
        try xcodeproj.write(path: projectPath)

        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: tempDir.path))

        let hasResult = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "has_dependency": .string("AppB"),
        ])
        let hasText = textContent(hasResult)
        #expect(hasText.contains("AppA"))
        #expect(!hasText.contains("- AppB ["))
        #expect(hasText.contains("1 match"))

        let missingResult = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "missing_dependency": .string("AppB"),
        ])
        let missingText = textContent(missingResult)
        // AppA has AppB dep -> excluded; AppB has none -> included
        #expect(missingText.contains("- AppB ["))
        #expect(!missingText.contains("- AppA ["))
        #expect(missingText.contains("1 match"))
    }

    @Test func `list targets has setting with value substring`() throws {
        let (tool, projectPath) = try makeTwoTargetTool(target1: "AppA", target2: "AppB")
        // Default helper sets PRODUCT_NAME = targetName
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "has_setting": .object([
                "name": .string("PRODUCT_NAME"),
                "value": .string("AppA"),
            ]),
        ])
        let text = textContent(result)
        #expect(text.contains("- AppA ["))
        #expect(!text.contains("- AppB ["))
        #expect(text.contains("1 match"))
    }

    @Test func `list targets missing setting`() throws {
        let (tool, projectPath) = try makeTwoTargetTool(target1: "AppA", target2: "AppB")
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "missing_setting": .string("MERGEABLE_LIBRARY"),
        ])
        let text = textContent(result)
        #expect(text.contains("2 matches"))
    }

    private func makeTwoTargetTool(
        target1: String, target2: String,
    ) throws -> (ListTargetsTool, Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "Two.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "Two", target1: target1, target2: target2, at: projectPath,
        )
        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: tempDir.path))
        return (tool, projectPath)
    }

    private func textContent(_ result: CallTool.Result) -> String {
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }

    @Test func `list targets with empty project`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListTargetsTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // List targets in the created project
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("TestProject.xcodeproj"))
            #expect(content.contains("No targets found"))
        } else {
            Issue.record("Expected text content")
        }
    }
}
