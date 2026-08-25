import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct DocumentTypeToolsTests {
    // MARK: - Helper

    /// Creates a test project with an Info.plist that has INFOPLIST_FILE set.
    private func createProjectWithInfoPlist(
        tempDir: URL
    ) throws -> (
        projectPath: Path, plistPath: String,
    ) {
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Create Info.plist
        let plistDir = tempDir.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: plistDir, withIntermediateDirectories: true)
        let plistPath = plistDir.appendingPathComponent("Info.plist").path
        let emptyPlist: [String: Any] = [:]
        let data = try PropertyListSerialization.data(
            fromPropertyList: emptyPlist, format: .xml, options: 0,
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

    // MARK: - ListDocumentTypesTool Tests

    @Test
    func `ListDocumentTypesTool tool creation`() {
        let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "list_document_types")
    }

    @Test
    func `ListDocumentTypesTool with missing parameters`() throws {
        let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path")])
        }
    }

    @Test
    func `ListDocumentTypesTool with non-existent target`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `ListDocumentTypesTool with no document types`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No document types"))
    }

    @Test
    func `ListDocumentTypesTool with existing document types`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Write document types to plist
        let plist: [String: AnyValue] = [
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeName": "Thesis Document",
                    "LSItemContentTypes": ["app.toba.thesis.project"],
                    "CFBundleTypeRole": "Editor",
                    "LSHandlerRank": "Owner",
                    "NSDocumentClass": "$(PRODUCT_MODULE_NAME).Document",
                ]
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Thesis Document"))
        #expect(message.contains("app.toba.thesis.project"))
        #expect(message.contains("Editor"))
        #expect(message.contains("Owner"))
    }

    // MARK: - ManageDocumentTypeTool Tests

    @Test
    func `ManageDocumentTypeTool tool creation`() {
        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "manage_document_type")
    }

    @Test
    func `ManageDocumentTypeTool with missing parameters`() throws {
        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                "action": .string("add"),
            ])
        }
    }

    @Test
    func `ManageDocumentTypeTool add document type`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("Test Document"),
            "content_types": .array([.string("com.example.test")]),
            "role": .string("Editor"),
            "handler_rank": .string("Owner"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        // Verify plist contents
        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let docTypes = plist["CFBundleDocumentTypes"]?.dictionaryArrayValue
        #expect(docTypes?.count == 1)
        #expect(docTypes?.first?["CFBundleTypeName"]?.stringValue == "Test Document")
        #expect(docTypes?.first?["CFBundleTypeRole"]?.stringValue == "Editor")
        #expect(docTypes?.first?["LSHandlerRank"]?.stringValue == "Owner")
        let contentTypes = docTypes?.first?["LSItemContentTypes"]?.stringArrayValue
        #expect(contentTypes == ["com.example.test"])
    }

    @Test
    func `ManageDocumentTypeTool add duplicate`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "CFBundleDocumentTypes": [["CFBundleTypeName": "Test Document"]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("Test Document"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `ManageDocumentTypeTool update document type`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "CFBundleDocumentTypes": [
                ["CFBundleTypeName": "Test Document", "CFBundleTypeRole": "Viewer"]
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("Test Document"),
            "role": .string("Editor"),
            "handler_rank": .string("Owner"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully updated"))

        // Verify update
        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let docTypes = updated["CFBundleDocumentTypes"]?.dictionaryArrayValue
        #expect(docTypes?.first?["CFBundleTypeRole"]?.stringValue == "Editor")
        #expect(docTypes?.first?["LSHandlerRank"]?.stringValue == "Owner")
    }

    @Test
    func `ManageDocumentTypeTool update non-existent`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("NonExistent"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `ManageDocumentTypeTool remove document type`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "CFBundleDocumentTypes": [["CFBundleTypeName": "Test Document"]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "name": .string("Test Document"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        // Verify removal - key should be gone entirely
        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        #expect(updated["CFBundleDocumentTypes"] == nil)
    }

    @Test
    func `ManageDocumentTypeTool with additional_properties`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("Custom Doc"),
            "additional_properties": .string("{\"CustomKey\": \"CustomValue\"}"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let docTypes = plist["CFBundleDocumentTypes"]?.dictionaryArrayValue
        #expect(docTypes?.first?["CustomKey"]?.stringValue == "CustomValue")
    }

    @Test
    func `ManageDocumentTypeTool materializes Info.plist when missing`() throws {
        let tempDir = TemporaryDirectory.url

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // No Info.plist exists, tool should materialize one
        let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("New Doc"),
            "content_types": .array([.string("com.example.new")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        // Verify plist was created
        let expectedPlistPath = tempDir.appendingPathComponent("App/Info.plist").path
        #expect(FileManager.default.fileExists(atPath: expectedPlistPath))
    }

    // MARK: - Full Workflow

    @Test
    func `Full workflow: add, list, update, list, remove`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)
        let basePath = tempDir.path

        // Add
        let manageTool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: basePath))
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "name": .string("My Document"),
            "content_types": .array([.string("com.example.doc")]),
            "role": .string("Editor"),
        ])

        // List
        let listTool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: basePath))
        let listResult = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage, _, _) = listResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage.contains("My Document"))
        #expect(listMessage.contains("com.example.doc"))

        // Update
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "name": .string("My Document"),
            "role": .string("Viewer"),
        ])

        // List again to verify update
        let listResult2 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage2, _, _) = listResult2.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage2.contains("Viewer"))

        // Remove
        let removeResult = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "name": .string("My Document"),
        ])
        guard case let .text(removeMessage, _, _) = removeResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(removeMessage.contains("Successfully removed"))

        // List should be empty
        let listResult3 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage3, _, _) = listResult3.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage3.contains("No document types"))
    }
}
