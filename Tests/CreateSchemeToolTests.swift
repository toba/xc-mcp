import MCP
import PathKit
import Testing
import XcodeProj
import XCMCPCore
import Foundation
@testable import XCMCPTools

struct CreateSchemeToolTests {
    @Test
    func `Tool name and description are correct`() {
        let tool = CreateSchemeTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "create_scheme")
        #expect(definition.description?.contains("scheme") == true)
    }

    @Test
    func `Missing required parameters throws`() {
        let tool = CreateSchemeTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "scheme_name": .string("App"),
            ])
        }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path/to/project.xcodeproj"),
            ])
        }
    }

    @Test
    func `Create scheme with debug_as_which_user sets attribute`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = CreateSchemeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "scheme_name": .string("AppScheme"),
            "build_target": .string("App"),
            "debug_as_which_user": .string("root"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Created scheme 'AppScheme'"))

        // Read back the scheme and verify debugAsWhichUser
        let schemePath = Path(
            "\(projectPath.string)/xcshareddata/xcschemes/AppScheme.xcscheme",
        )
        let scheme = try XCScheme(path: schemePath)
        #expect(scheme.launchAction?.debugAsWhichUser == "root")
    }

    @Test
    func `Create scheme without debug_as_which_user omits attribute`() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = CreateSchemeTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "scheme_name": .string("AppScheme"),
            "build_target": .string("App"),
        ])

        let schemePath = Path(
            "\(projectPath.string)/xcshareddata/xcschemes/AppScheme.xcscheme",
        )
        let scheme = try XCScheme(path: schemePath)
        #expect(scheme.launchAction?.debugAsWhichUser == nil)
    }
}
