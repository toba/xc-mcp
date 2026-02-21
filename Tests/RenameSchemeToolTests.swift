import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
@testable import XCMCPTools

@Suite("RenameSchemeTool Tests")
struct RenameSchemeToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RenameSchemeTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "rename_scheme")
        #expect(toolDefinition.description == "Rename an Xcode scheme file on disk")
    }

    @Test("Rename scheme with missing parameters")
    func renameSchemeWithMissingParameters() throws {
        let tool = RenameSchemeTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "scheme_name": Value.string("App"),
                "new_name": Value.string("NewApp"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "new_name": Value.string("NewApp"),
            ])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "scheme_name": Value.string("App"),
            ])
        }
    }

    @Test("Rename existing scheme")
    func renameExistingScheme() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a scheme file
        let schemesDir = projectPath.string + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(
            atPath: schemesDir, withIntermediateDirectories: true
        )
        let schemeContent = "<Scheme></Scheme>"
        try schemeContent.write(
            toFile: "\(schemesDir)/OldScheme.xcscheme", atomically: true, encoding: .utf8
        )

        let tool = RenameSchemeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "scheme_name": Value.string("OldScheme"),
            "new_name": Value.string("NewScheme"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully renamed scheme 'OldScheme' to 'NewScheme'"))

        // Verify file was renamed
        #expect(FileManager.default.fileExists(atPath: "\(schemesDir)/NewScheme.xcscheme"))
        #expect(!FileManager.default.fileExists(atPath: "\(schemesDir)/OldScheme.xcscheme"))
    }

    @Test("Rename non-existent scheme")
    func renameNonExistentScheme() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = RenameSchemeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "scheme_name": Value.string("NonExistent"),
            "new_name": Value.string("NewScheme"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Rename scheme with name conflict")
    func renameSchemeWithNameConflict() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create two scheme files
        let schemesDir = projectPath.string + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(
            atPath: schemesDir, withIntermediateDirectories: true
        )
        try "<Scheme></Scheme>".write(
            toFile: "\(schemesDir)/SchemeA.xcscheme", atomically: true, encoding: .utf8
        )
        try "<Scheme></Scheme>".write(
            toFile: "\(schemesDir)/SchemeB.xcscheme", atomically: true, encoding: .utf8
        )

        let tool = RenameSchemeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "scheme_name": Value.string("SchemeA"),
            "new_name": Value.string("SchemeB"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }
}
