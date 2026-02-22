import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("URLTypeTools Tests")
struct URLTypeToolsTests {
    // MARK: - Helper

    /// Creates a test project with an Info.plist that has INFOPLIST_FILE set.
    private func createProjectWithInfoPlist(tempDir: URL) throws -> (
        projectPath: Path, plistPath: String
    ) {
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // Create Info.plist
        let plistDir = tempDir.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: plistDir, withIntermediateDirectories: true)
        let plistPath = plistDir.appendingPathComponent("Info.plist").path
        let emptyPlist: [String: Any] = [:]
        let data = try PropertyListSerialization.data(
            fromPropertyList: emptyPlist, format: .xml, options: 0
        )
        try data.write(to: URL(fileURLWithPath: plistPath))

        // Set INFOPLIST_FILE
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["INFOPLIST_FILE"] = "App/Info.plist"
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        return (projectPath, plistPath)
    }

    // MARK: - ListURLTypesTool Tests

    @Test("ListURLTypesTool tool creation")
    func listURLTypesToolCreation() {
        let tool = ListURLTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "list_url_types")
    }

    @Test("ListURLTypesTool with missing parameters")
    func listURLTypesMissingParams() throws {
        let tool = ListURLTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path")])
        }
    }

    @Test("ListURLTypesTool with non-existent target")
    func listURLTypesNonExistentTarget() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListURLTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("ListURLTypesTool with no URL types")
    func listURLTypesEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListURLTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No URL types"))
    }

    @Test("ListURLTypesTool with existing URL types")
    func listURLTypesWithEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Write URL types to plist
        let plist: [String: Any] = [
            "CFBundleURLTypes": [
                [
                    "CFBundleURLName": "app.toba.ThesisApp",
                    "CFBundleURLSchemes": ["thesisapp"],
                    "CFBundleTypeRole": "Editor",
                ] as [String: Any]
            ] as [[String: Any]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListURLTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("app.toba.ThesisApp"))
        #expect(message.contains("thesisapp"))
        #expect(message.contains("Editor"))
    }

    // MARK: - ManageURLTypeTool Tests

    @Test("ManageURLTypeTool tool creation")
    func manageURLTypeToolCreation() {
        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "manage_url_type")
    }

    @Test("ManageURLTypeTool with missing parameters")
    func manageURLTypeMissingParams() throws {
        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                "action": .string("add"),
            ])
        }
    }

    @Test("ManageURLTypeTool add URL type")
    func manageURLTypeAdd() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("com.example.myapp"),
            "url_schemes": .array([.string("myapp"), .string("myapp-dev")]),
            "role": .string("Editor"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        // Verify plist contents
        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        #expect(urlTypes?.count == 1)
        #expect(urlTypes?.first?["CFBundleURLName"] as? String == "com.example.myapp")
        #expect(urlTypes?.first?["CFBundleTypeRole"] as? String == "Editor")
        let schemes = urlTypes?.first?["CFBundleURLSchemes"] as? [String]
        #expect(schemes == ["myapp", "myapp-dev"])
    }

    @Test("ManageURLTypeTool add duplicate")
    func manageURLTypeAddDuplicate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "CFBundleURLTypes": [
                ["CFBundleURLName": "com.example.myapp"] as [String: Any]
            ] as [[String: Any]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("com.example.myapp"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("ManageURLTypeTool update URL type")
    func manageURLTypeUpdate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "CFBundleURLTypes": [
                [
                    "CFBundleURLName": "com.example.myapp",
                    "CFBundleTypeRole": "Viewer",
                    "CFBundleURLSchemes": ["myapp"],
                ] as [String: Any]
            ] as [[String: Any]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("com.example.myapp"),
            "role": .string("Editor"),
            "url_schemes": .array([.string("myapp"), .string("myapp-beta")]),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully updated"))

        // Verify update
        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let urlTypes = updated["CFBundleURLTypes"] as? [[String: Any]]
        #expect(urlTypes?.first?["CFBundleTypeRole"] as? String == "Editor")
        let schemes = urlTypes?.first?["CFBundleURLSchemes"] as? [String]
        #expect(schemes == ["myapp", "myapp-beta"])
    }

    @Test("ManageURLTypeTool update non-existent")
    func manageURLTypeUpdateNotFound() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("NonExistent"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("ManageURLTypeTool remove URL type")
    func manageURLTypeRemove() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "CFBundleURLTypes": [
                ["CFBundleURLName": "com.example.myapp"] as [String: Any]
            ] as [[String: Any]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "name": .string("com.example.myapp"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        // Verify removal - key should be gone entirely
        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        #expect(updated["CFBundleURLTypes"] == nil)
    }

    @Test("ManageURLTypeTool with additional_properties")
    func manageURLTypeAdditionalProperties() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("com.example.custom"),
            "additional_properties": .string("{\"CustomKey\": \"CustomValue\"}"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]]
        #expect(urlTypes?.first?["CustomKey"] as? String == "CustomValue")
    }

    @Test("ManageURLTypeTool materializes Info.plist when missing")
    func manageURLTypeMaterialize() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath
        )

        // No Info.plist exists, tool should materialize one
        let tool = ManageURLTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("com.example.newapp"),
            "url_schemes": .array([.string("newapp")]),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        // Verify plist was created
        let expectedPlistPath = tempDir.appendingPathComponent("App/Info.plist").path
        #expect(FileManager.default.fileExists(atPath: expectedPlistPath))
    }

    // MARK: - Full Workflow

    @Test("Full workflow: add, list, update, list, remove")
    func fullURLTypeWorkflow() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)
        let basePath = tempDir.path

        // Add
        let manageTool = ManageURLTypeTool(pathUtility: PathUtility(basePath: basePath))
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("app.toba.ThesisApp"),
            "url_schemes": .array([.string("thesisapp")]),
            "role": .string("Editor"),
        ])

        // List
        let listTool = ListURLTypesTool(pathUtility: PathUtility(basePath: basePath))
        let listResult = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage) = listResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage.contains("app.toba.ThesisApp"))
        #expect(listMessage.contains("thesisapp"))

        // Update
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("app.toba.ThesisApp"),
            "role": .string("Viewer"),
            "url_schemes": .array([.string("thesisapp"), .string("thesis")]),
        ])

        // List again to verify update
        let listResult2 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage2) = listResult2.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage2.contains("Viewer"))
        #expect(listMessage2.contains("thesis"))

        // Remove
        let removeResult = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "name": .string("app.toba.ThesisApp"),
        ])
        guard case let .text(removeMessage) = removeResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(removeMessage.contains("Successfully removed"))

        // List should be empty
        let listResult3 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage3) = listResult3.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage3.contains("No URL types"))
    }
}
