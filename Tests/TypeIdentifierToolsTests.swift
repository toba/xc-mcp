import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite("TypeIdentifierTools Tests")
struct TypeIdentifierToolsTests {
    // MARK: - Helper

    private func createProjectWithInfoPlist(tempDir: URL) throws -> (
        projectPath: Path, plistPath: String,
    ) {
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let plistDir = tempDir.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: plistDir, withIntermediateDirectories: true)
        let plistPath = plistDir.appendingPathComponent("Info.plist").path
        let emptyPlist: [String: Any] = [:]
        let data = try PropertyListSerialization.data(
            fromPropertyList: emptyPlist, format: .xml, options: 0,
        )
        try data.write(to: URL(fileURLWithPath: plistPath))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        for config in target.buildConfigurationList?.buildConfigurations ?? [] {
            config.buildSettings["INFOPLIST_FILE"] = "App/Info.plist"
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        return (projectPath, plistPath)
    }

    // MARK: - ListTypeIdentifiersTool Tests

    @Test("ListTypeIdentifiersTool tool creation")
    func listTypeIdentifiersToolCreation() {
        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "list_type_identifiers")
    }

    @Test("ListTypeIdentifiersTool with missing parameters")
    func listTypeIdentifiersMissingParams() throws {
        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path")])
        }
    }

    @Test("ListTypeIdentifiersTool with no identifiers")
    func listTypeIdentifiersEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No exported or imported type identifiers"))
    }

    @Test("ListTypeIdentifiersTool with exported identifiers")
    func listTypeIdentifiersExported() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: Any] = [
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeIdentifier": "app.toba.thesis.project",
                    "UTTypeDescription": "Thesis Document",
                    "UTTypeConformsTo": ["com.apple.package"],
                    "UTTypeTagSpecification": [
                        "public.filename-extension": ["thesis.project"],
                    ],
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("exported"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("app.toba.thesis.project"))
        #expect(message.contains("Thesis Document"))
        #expect(message.contains("com.apple.package"))
        #expect(message.contains("thesis.project"))
    }

    @Test("ListTypeIdentifiersTool with kind=all shows both")
    func listTypeIdentifiersAll() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: Any] = [
            "UTExportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.exported"] as [String: Any],
            ] as [[String: Any]],
            "UTImportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.imported"] as [String: Any],
            ] as [[String: Any]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("all"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("com.example.exported"))
        #expect(message.contains("com.example.imported"))
        #expect(message.contains("Exported"))
        #expect(message.contains("Imported"))
    }

    // MARK: - ManageTypeIdentifierTool Tests

    @Test("ManageTypeIdentifierTool tool creation")
    func manageTypeIdentifierToolCreation() {
        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "manage_type_identifier")
    }

    @Test("ManageTypeIdentifierTool with missing parameters")
    func manageTypeIdentifierMissingParams() throws {
        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/path"),
                "target_name": .string("App"),
                "action": .string("add"),
                "kind": .string("exported"),
            ])
        }
    }

    @Test("ManageTypeIdentifierTool add exported type")
    func manageTypeIdentifierAddExported() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("exported"),
            "identifier": .string("app.toba.thesis.project"),
            "description": .string("Thesis Document"),
            "conforms_to": .array([.string("com.apple.package")]),
            "extensions": .array([.string("thesis.project")]),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))
        #expect(message.contains("exported"))

        // Verify plist
        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let exported = plist["UTExportedTypeDeclarations"] as? [[String: Any]]
        #expect(exported?.count == 1)
        #expect(exported?.first?["UTTypeIdentifier"] as? String == "app.toba.thesis.project")
        #expect(exported?.first?["UTTypeDescription"] as? String == "Thesis Document")

        let tagSpec = exported?.first?["UTTypeTagSpecification"] as? [String: Any]
        let extensions = tagSpec?["public.filename-extension"] as? [String]
        #expect(extensions == ["thesis.project"])
    }

    @Test("ManageTypeIdentifierTool add imported type")
    func manageTypeIdentifierAddImported() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("imported"),
            "identifier": .string("org.example.format"),
            "description": .string("Example Format"),
            "mime_types": .array([.string("application/x-example")]),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))
        #expect(message.contains("imported"))

        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let imported = plist["UTImportedTypeDeclarations"] as? [[String: Any]]
        #expect(imported?.count == 1)
        #expect(imported?.first?["UTTypeIdentifier"] as? String == "org.example.format")
    }

    @Test("ManageTypeIdentifierTool add duplicate")
    func manageTypeIdentifierAddDuplicate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "UTExportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.dup"] as [String: Any],
            ] as [[String: Any]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("exported"),
            "identifier": .string("com.example.dup"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("ManageTypeIdentifierTool update type")
    func manageTypeIdentifierUpdate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeIdentifier": "com.example.type",
                    "UTTypeDescription": "Old Description",
                ] as [String: Any],
            ] as [[String: Any]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "kind": .string("exported"),
            "identifier": .string("com.example.type"),
            "description": .string("New Description"),
            "icon_name": .string("MyIcon"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully updated"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let exported = updated["UTExportedTypeDeclarations"] as? [[String: Any]]
        #expect(exported?.first?["UTTypeDescription"] as? String == "New Description")
        #expect(exported?.first?["UTTypeIconName"] as? String == "MyIcon")
    }

    @Test("ManageTypeIdentifierTool remove type")
    func manageTypeIdentifierRemove() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: Any] = [
            "UTExportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.remove"] as [String: Any],
            ] as [[String: Any]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "kind": .string("exported"),
            "identifier": .string("com.example.remove"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        #expect(updated["UTExportedTypeDeclarations"] == nil)
    }

    @Test("ManageTypeIdentifierTool materializes Info.plist when missing")
    func manageTypeIdentifierMaterialize() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("exported"),
            "identifier": .string("com.example.new"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        let expectedPlistPath = tempDir.appendingPathComponent("App/Info.plist").path
        #expect(FileManager.default.fileExists(atPath: expectedPlistPath))
    }

    // MARK: - Full Workflow

    @Test("Full workflow: add exported, add imported, list all, remove")
    func fullTypeIdentifierWorkflow() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)
        let basePath = tempDir.path

        let manageTool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: basePath))

        // Add exported
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("exported"),
            "identifier": .string("com.example.my-format"),
            "description": .string("My Format"),
            "conforms_to": .array([.string("public.data")]),
            "extensions": .array([.string("myf")]),
        ])

        // Add imported
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("add"),
            "kind": .string("imported"),
            "identifier": .string("org.third-party.format"),
            "description": .string("Third Party Format"),
        ])

        // List all
        let listTool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: basePath))
        let listResult = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(listMessage) = listResult.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage.contains("com.example.my-format"))
        #expect(listMessage.contains("org.third-party.format"))

        // Remove exported
        _ = try manageTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "kind": .string("exported"),
            "identifier": .string("com.example.my-format"),
        ])

        // List exported only - should be empty
        let listResult2 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("exported"),
        ])
        guard case let .text(listMessage2) = listResult2.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage2.contains("No exported type identifiers"))

        // Imported should still be there
        let listResult3 = try listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("imported"),
        ])
        guard case let .text(listMessage3) = listResult3.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage3.contains("org.third-party.format"))
    }
}
