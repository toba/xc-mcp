import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("DocumentTypeTools Tests")
struct DocumentTypeToolsTests {
  // MARK: - Helper

  /// Creates a test project with an Info.plist that has INFOPLIST_FILE set.
  private func createProjectWithInfoPlist(tempDir: URL) throws -> (
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

  @Test("ListDocumentTypesTool tool creation")
  func listDocumentTypesToolCreation() {
    let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
    let definition = tool.tool()
    #expect(definition.name == "list_document_types")
  }

  @Test("ListDocumentTypesTool with missing parameters")
  func listDocumentTypesMissingParams() throws {
    let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: "/tmp"))
    #expect(throws: MCPError.self) {
      try tool.execute(arguments: ["project_path": .string("/path")])
    }
  }

  @Test("ListDocumentTypesTool with non-existent target")
  func listDocumentTypesNonExistentTarget() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

    let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("NonExistent"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("not found"))
  }

  @Test("ListDocumentTypesTool with no document types")
  func listDocumentTypesEmpty() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

    let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("No document types"))
  }

  @Test("ListDocumentTypesTool with existing document types")
  func listDocumentTypesWithEntries() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

    // Write document types to plist
    let plist: [String: Any] = [
      "CFBundleDocumentTypes": [
        [
          "CFBundleTypeName": "Thesis Document",
          "LSItemContentTypes": ["app.toba.thesis.project"],
          "CFBundleTypeRole": "Editor",
          "LSHandlerRank": "Owner",
          "NSDocumentClass": "$(PRODUCT_MODULE_NAME).Document",
        ] as [String: Any]
      ] as [[String: Any]]
    ]
    try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

    let tool = ListDocumentTypesTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Thesis Document"))
    #expect(message.contains("app.toba.thesis.project"))
    #expect(message.contains("Editor"))
    #expect(message.contains("Owner"))
  }

  // MARK: - ManageDocumentTypeTool Tests

  @Test("ManageDocumentTypeTool tool creation")
  func manageDocumentTypeToolCreation() {
    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
    let definition = tool.tool()
    #expect(definition.name == "manage_document_type")
  }

  @Test("ManageDocumentTypeTool with missing parameters")
  func manageDocumentTypeMissingParams() throws {
    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: "/tmp"))
    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "project_path": .string("/path"),
        "target_name": .string("App"),
        "action": .string("add"),
      ])
    }
  }

  @Test("ManageDocumentTypeTool add document type")
  func manageDocumentTypeAdd() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

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

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully added"))

    // Verify plist contents
    let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
    let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]]
    #expect(docTypes?.count == 1)
    #expect(docTypes?.first?["CFBundleTypeName"] as? String == "Test Document")
    #expect(docTypes?.first?["CFBundleTypeRole"] as? String == "Editor")
    #expect(docTypes?.first?["LSHandlerRank"] as? String == "Owner")
    let contentTypes = docTypes?.first?["LSItemContentTypes"] as? [String]
    #expect(contentTypes == ["com.example.test"])
  }

  @Test("ManageDocumentTypeTool add duplicate")
  func manageDocumentTypeAddDuplicate() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

    // Pre-populate
    let plist: [String: Any] = [
      "CFBundleDocumentTypes": [
        ["CFBundleTypeName": "Test Document"] as [String: Any]
      ] as [[String: Any]]
    ]
    try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
      "action": .string("add"),
      "name": .string("Test Document"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("already exists"))
  }

  @Test("ManageDocumentTypeTool update document type")
  func manageDocumentTypeUpdate() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

    // Pre-populate
    let plist: [String: Any] = [
      "CFBundleDocumentTypes": [
        [
          "CFBundleTypeName": "Test Document",
          "CFBundleTypeRole": "Viewer",
        ] as [String: Any]
      ] as [[String: Any]]
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

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully updated"))

    // Verify update
    let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
    let docTypes = updated["CFBundleDocumentTypes"] as? [[String: Any]]
    #expect(docTypes?.first?["CFBundleTypeRole"] as? String == "Editor")
    #expect(docTypes?.first?["LSHandlerRank"] as? String == "Owner")
  }

  @Test("ManageDocumentTypeTool update non-existent")
  func manageDocumentTypeUpdateNotFound() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, _) = try createProjectWithInfoPlist(tempDir: tempDir)

    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
      "action": .string("update"),
      "name": .string("NonExistent"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("not found"))
  }

  @Test("ManageDocumentTypeTool remove document type")
  func manageDocumentTypeRemove() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

    // Pre-populate
    let plist: [String: Any] = [
      "CFBundleDocumentTypes": [
        ["CFBundleTypeName": "Test Document"] as [String: Any]
      ] as [[String: Any]]
    ]
    try InfoPlistUtility.writeInfoPlist(plist, toPath: plistPath)

    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
      "action": .string("remove"),
      "name": .string("Test Document"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully removed"))

    // Verify removal - key should be gone entirely
    let updated = try InfoPlistUtility.readInfoPlist(path: plistPath)
    #expect(updated["CFBundleDocumentTypes"] == nil)
  }

  @Test("ManageDocumentTypeTool with additional_properties")
  func manageDocumentTypeAdditionalProperties() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let (projectPath, plistPath) = try createProjectWithInfoPlist(tempDir: tempDir)

    let tool = ManageDocumentTypeTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
      "action": .string("add"),
      "name": .string("Custom Doc"),
      "additional_properties": .string("{\"CustomKey\": \"CustomValue\"}"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully added"))

    let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)
    let docTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]]
    #expect(docTypes?.first?["CustomKey"] as? String == "CustomValue")
  }

  @Test("ManageDocumentTypeTool materializes Info.plist when missing")
  func manageDocumentTypeMaterialize() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

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

    guard case .text(let message) = result.content.first else {
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
  func fullDocumentTypeWorkflow() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

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
    guard case .text(let listMessage) = listResult.content.first else {
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
    guard case .text(let listMessage2) = listResult2.content.first else {
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
    guard case .text(let removeMessage) = removeResult.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(removeMessage.contains("Successfully removed"))

    // List should be empty
    let listResult3 = try listTool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "target_name": .string("App"),
    ])
    guard case .text(let listMessage3) = listResult3.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(listMessage3.contains("No document types"))
  }
}
