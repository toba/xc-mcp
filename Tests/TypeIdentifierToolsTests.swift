import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct TypeIdentifierToolsTests {
    // MARK: - Helper

    private func createProjectWithInfoPlist(
        tempDir: URL
    ) throws -> (
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

    @Test
    func `ListTypeIdentifiersTool tool creation`() {
        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "list_type_identifiers")
    }

    @Test
    func `ListTypeIdentifiersTool with missing parameters`() throws {
        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/path")])
        }
    }

    @Test
    func `ListTypeIdentifiersTool with no identifiers`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No exported or imported type identifiers"))
    }

    @Test
    func `ListTypeIdentifiersTool with exported identifiers`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: AnyValue] = [
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeIdentifier": "app.toba.thesis.project",
                    "UTTypeDescription": "Thesis Document",
                    "UTTypeConformsTo": ["com.apple.package"],
                    "UTTypeTagSpecification": ["public.filename-extension": ["thesis.project"]],
                ]
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("exported"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("app.toba.thesis.project"))
        #expect(message.contains("Thesis Document"))
        #expect(message.contains("com.apple.package"))
        #expect(message.contains("thesis.project"))
    }

    @Test
    func `ListTypeIdentifiersTool with kind=all shows both`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: AnyValue] = [
            "UTExportedTypeDeclarations": [["UTTypeIdentifier": "com.example.exported"]],
            "UTImportedTypeDeclarations": [["UTTypeIdentifier": "com.example.imported"]],
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ListTypeIdentifiersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "kind": .string("all"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("com.example.exported"))
        #expect(message.contains("com.example.imported"))
        #expect(message.contains("Exported"))
        #expect(message.contains("Imported"))
    }

    // MARK: - ManageTypeIdentifierTool Tests

    @Test
    func `ManageTypeIdentifierTool tool creation`() {
        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: "/tmp"))
        let definition = tool.tool()
        #expect(definition.name == "manage_type_identifier")
    }

    @Test
    func `ManageTypeIdentifierTool with missing parameters`() throws {
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

    @Test
    func `ManageTypeIdentifierTool add exported type`() throws {
        let tempDir = TemporaryDirectory.url

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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))
        #expect(message.contains("exported"))

        // Verify plist
        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let exported = plist["UTExportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(exported?.count == 1)
        #expect(exported?.first?["UTTypeIdentifier"]?.stringValue == "app.toba.thesis.project")
        #expect(exported?.first?["UTTypeDescription"]?.stringValue == "Thesis Document")

        let tagSpec = exported?.first?["UTTypeTagSpecification"]?.dictionaryValue
        let extensions = tagSpec?["public.filename-extension"]?.stringArrayValue
        #expect(extensions == ["thesis.project"])
    }

    @Test
    func `ManageTypeIdentifierTool add imported type`() throws {
        let tempDir = TemporaryDirectory.url

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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))
        #expect(message.contains("imported"))

        let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let imported = plist["UTImportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(imported?.count == 1)
        #expect(imported?.first?["UTTypeIdentifier"]?.stringValue == "org.example.format")
    }

    @Test
    func `ManageTypeIdentifierTool add duplicate`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "UTExportedTypeDeclarations": [["UTTypeIdentifier": "com.example.dup"]]
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `ManageTypeIdentifierTool update type`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "UTExportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.type", "UTTypeDescription": "Old Description"]

            ]
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully updated"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let exported = updated["UTExportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(exported?.first?["UTTypeDescription"]?.stringValue == "New Description")
        #expect(exported?.first?["UTTypeIconName"]?.stringValue == "MyIcon")
    }

    @Test
    func `ManageTypeIdentifierTool remove type`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Pre-populate
        let plist: [String: AnyValue] = [
            "UTExportedTypeDeclarations": [["UTTypeIdentifier": "com.example.remove"]]
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        #expect(updated["UTExportedTypeDeclarations"] == nil)
    }

    @Test
    func `ManageTypeIdentifierTool materializes Info.plist when missing`() throws {
        let tempDir = TemporaryDirectory.url

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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added"))

        let expectedPlistPath = tempDir.appendingPathComponent("App/Info.plist").path
        #expect(FileManager.default.fileExists(atPath: expectedPlistPath))
    }

    @Test
    func `ManageTypeIdentifierTool update backfills identifier matched by description`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        // Malformed entry: has a description but no UTTypeIdentifier.
        let plist: [String: AnyValue] = [
            "UTImportedTypeDeclarations": [
                [
                    "UTTypeDescription": "BibTeX Document",
                    "UTTypeTagSpecification": ["public.filename-extension": ["bib"]],
                ]
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("update"),
            "kind": .string("imported"),
            "match_description": .string("BibTeX Document"),
            "identifier": .string("org.tug.tex.bibtex"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully updated"))
        #expect(message.contains("org.tug.tex.bibtex"))

        // Still a single entry, now with a backfilled identifier.
        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let imported = updated["UTImportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(imported?.count == 1)
        #expect(imported?.first?["UTTypeIdentifier"]?.stringValue == "org.tug.tex.bibtex")
        #expect(imported?.first?["UTTypeDescription"]?.stringValue == "BibTeX Document")
    }

    @Test
    func `ManageTypeIdentifierTool remove by index`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: AnyValue] = [
            "UTImportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.first"],
                // Malformed: no identifier, can only be addressed by index.
                ["UTTypeDescription": "Citation Style Language"],
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("remove"),
            "kind": .string("imported"),
            "match_index": .int(2),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let imported = updated["UTImportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(imported?.count == 1)
        #expect(imported?.first?["UTTypeIdentifier"]?.stringValue == "com.example.first")
    }

    @Test
    func `ManageTypeIdentifierTool prune removes malformed declarations`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: AnyValue] = [
            "UTImportedTypeDeclarations": [
                ["UTTypeIdentifier": "com.example.valid"],
                ["UTTypeDescription": "BibTeX Document"],
                ["UTTypeDescription": "Research Information Systems"],
            ]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("prune"),
            "kind": .string("imported"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Pruned 2"))

        let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
        let imported = updated["UTImportedTypeDeclarations"]?.dictionaryArrayValue
        #expect(imported?.count == 1)
        #expect(imported?.first?["UTTypeIdentifier"]?.stringValue == "com.example.valid")
    }

    @Test
    func `ManageTypeIdentifierTool prune reports when nothing malformed`() throws {
        let tempDir = TemporaryDirectory.url

        let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

        let plist: [String: AnyValue] = [
            "UTImportedTypeDeclarations": [["UTTypeIdentifier": "com.example.valid"]]
        ]
        try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

        let tool = ManageTypeIdentifierTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "action": .string("prune"),
            "kind": .string("imported"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No malformed"))
    }

    @Test
    func `ManageTypeIdentifierTool add still requires identifier`() throws {
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

    // MARK: - Full Workflow

    @Test
    func `Full workflow: add exported, add imported, list all, remove`() throws {
        let tempDir = TemporaryDirectory.url

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
        guard case let .text(listMessage, _, _) = listResult.content.first else {
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
        guard case let .text(listMessage2, _, _) = listResult2.content.first else {
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
        guard case let .text(listMessage3, _, _) = listResult3.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(listMessage3.contains("org.third-party.format"))
    }
}
