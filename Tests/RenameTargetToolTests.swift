import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("RenameTargetTool Tests")
struct RenameTargetToolTests {
  @Test("Tool creation")
  func toolCreation() {
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
    let toolDefinition = tool.tool()

    #expect(toolDefinition.name == "rename_target")
    #expect(
      toolDefinition.description
        == "Rename an existing target in-place, updating all references",
    )
  }

  @Test("Rename target with missing parameters")
  func renameTargetWithMissingParameters() throws {
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

    // Missing project_path
    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "target_name": Value.string("App"),
        "new_name": Value.string("NewApp"),
      ])
    }

    // Missing target_name
    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "project_path": Value.string("/path/to/project.xcodeproj"),
        "new_name": Value.string("NewApp"),
      ])
    }

    // Missing new_name
    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "project_path": Value.string("/path/to/project.xcodeproj"),
        "target_name": Value.string("App"),
      ])
    }
  }

  @Test("Rename existing target")
  func renameExistingTarget() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed target 'App' to 'NewApp'"))

    // Verify target was renamed
    let xcodeproj = try XcodeProj(path: projectPath)
    let renamedTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
    #expect(renamedTarget != nil)

    // Verify old name is gone
    let oldTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
    #expect(oldTarget == nil)

    // Verify PRODUCT_NAME updated
    let buildConfig = renamedTarget?.buildConfigurationList?.buildConfigurations.first
    #expect(buildConfig?.buildSettings["PRODUCT_NAME"]?.stringValue == "NewApp")

    // Verify BUNDLE_IDENTIFIER preserved (not changed)
    #expect(
      buildConfig?.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.example.App",
    )
  }

  @Test("Rename non-existent target")
  func renameNonExistentTarget() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("NonExistentTarget"),
      "new_name": Value.string("NewTarget"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("not found"))
  }

  @Test("Rename to existing target name")
  func renameToExistingTargetName() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Add another target
    let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    _ = try addTargetTool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("ExistingTarget"),
      "product_type": Value.string("app"),
      "bundle_identifier": Value.string("com.test.existing"),
    ])

    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("ExistingTarget"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("already exists"))
  }

  @Test("Rename target with dependencies")
  func renameTargetWithDependencies() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Add a framework target
    let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    _ = try addTargetTool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("Framework"),
      "product_type": Value.string("framework"),
      "bundle_identifier": Value.string("com.test.framework"),
    ])

    // Add dependency: App depends on Framework
    let addDependencyTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
    _ = try addDependencyTool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "dependency_name": Value.string("Framework"),
    ])

    // Rename the framework target
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("Framework"),
      "new_name": Value.string("CoreLib"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify dependency reference was updated
    let xcodeproj = try XcodeProj(path: projectPath)
    let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
    let hasDependency = appTarget?.dependencies.contains { $0.name == "CoreLib" } ?? false
    #expect(hasDependency == true)
  }

  @Test("Rename target with product reference")
  func renameTargetWithProductReference() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Add a product reference to the target
    let xcodeproj = try XcodeProj(path: projectPath)
    let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
    let productRef = PBXFileReference(
      sourceTree: .buildProductsDir, name: "App.app", path: "App.app",
    )
    xcodeproj.pbxproj.add(object: productRef)
    target.product = productRef
    try PBXProjWriter.write(xcodeproj, to: projectPath)

    // Rename the target
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify product reference path was updated
    let updatedProj = try XcodeProj(path: projectPath)
    let renamedTarget = updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" }
    #expect(renamedTarget?.product?.path == "NewApp.app")
  }

  // MARK: - New tests for enhanced rename_target

  @Test("Rename target with new bundle identifier")
  func renameTargetWithBundleIdentifier() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
      "new_bundle_identifier": Value.string("com.example.NewApp"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify bundle identifiers updated
    let xcodeproj = try XcodeProj(path: projectPath)
    let renamedTarget = try #require(
      xcodeproj.pbxproj.nativeTargets.first { $0.name == "NewApp" },
    )
    for config in renamedTarget.buildConfigurationList?.buildConfigurations ?? [] {
      #expect(
        config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?.stringValue
          == "com.example.NewApp",
      )
      #expect(
        config.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.example.NewApp",
      )
    }
  }

  @Test("Rename target updates CODE_SIGN_ENTITLEMENTS")
  func renameTargetUpdatesEntitlements() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Add CODE_SIGN_ENTITLEMENTS to build settings
    let xcodeproj = try XcodeProj(path: projectPath)
    let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
    for config in target.buildConfigurationList?.buildConfigurations ?? [] {
      config.buildSettings["CODE_SIGN_ENTITLEMENTS"] = .string("App/App.entitlements")
    }
    try PBXProjWriter.write(xcodeproj, to: projectPath)

    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify entitlements path updated
    let updatedProj = try XcodeProj(path: projectPath)
    let renamedTarget = try #require(
      updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" },
    )
    let config = try #require(
      renamedTarget.buildConfigurationList?.buildConfigurations.first,
    )
    #expect(
      config.buildSettings["CODE_SIGN_ENTITLEMENTS"]?.stringValue
        == "NewApp/NewApp.entitlements",
    )
  }

  @Test("Rename target updates cross-target TEST_TARGET_NAME and TEST_HOST")
  func renameTargetUpdatesCrossTargetSettings() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Add a test target with TEST_TARGET_NAME and TEST_HOST
    let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    _ = try addTargetTool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("AppTests"),
      "product_type": Value.string("unit_test_bundle"),
      "bundle_identifier": Value.string("com.example.AppTests"),
    ])

    // Set TEST_TARGET_NAME and TEST_HOST on the test target
    let xcodeproj = try XcodeProj(path: projectPath)
    let testTarget = try #require(
      xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTests" },
    )
    for config in testTarget.buildConfigurationList?.buildConfigurations ?? [] {
      config.buildSettings["TEST_TARGET_NAME"] = .string("App")
      config.buildSettings["TEST_HOST"] = .string(
        "$(BUILT_PRODUCTS_DIR)/App.app/Contents/MacOS/App",
      )
    }
    try PBXProjWriter.write(xcodeproj, to: projectPath)

    // Rename the app target
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify test target settings updated
    let updatedProj = try XcodeProj(path: projectPath)
    let updatedTestTarget = try #require(
      updatedProj.pbxproj.nativeTargets.first { $0.name == "AppTests" },
    )
    let config = try #require(
      updatedTestTarget.buildConfigurationList?.buildConfigurations.first,
    )
    #expect(config.buildSettings["TEST_TARGET_NAME"]?.stringValue == "NewApp")
    #expect(
      config.buildSettings["TEST_HOST"]?.stringValue
        == "$(BUILT_PRODUCTS_DIR)/NewApp.app/Contents/MacOS/NewApp",
    )
  }

  @Test("Rename target updates scheme files")
  func renameTargetUpdatesSchemeFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Create a scheme file with BuildableName and BlueprintName
    let schemesDir = projectPath.string + "/xcshareddata/xcschemes"
    try FileManager.default.createDirectory(
      atPath: schemesDir, withIntermediateDirectories: true,
    )
    let schemeContent = """
      <?xml version="1.0" encoding="UTF-8"?>
      <Scheme>
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "ABC123"
            BuildableName = "App.app"
            BlueprintName = "App"
            ReferencedContainer = "container:TestProject.xcodeproj">
         </BuildableReference>
      </Scheme>
      """
    try schemeContent.write(
      toFile: "\(schemesDir)/App.xcscheme", atomically: true, encoding: .utf8,
    )

    // Rename the target
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))
    #expect(message.contains("updated 1 scheme file"))

    // Verify scheme file content was updated
    let updatedScheme = try String(
      contentsOfFile: "\(schemesDir)/App.xcscheme", encoding: .utf8,
    )
    #expect(updatedScheme.contains("BuildableName = \"NewApp.app\""))
    #expect(updatedScheme.contains("BlueprintName = \"NewApp\""))
    #expect(!updatedScheme.contains("BuildableName = \"App.app\""))
    #expect(!updatedScheme.contains("BlueprintName = \"App\""))
  }

  @Test("Rename target updates LD_RUNPATH_SEARCH_PATHS and FRAMEWORK_SEARCH_PATHS")
  func renameTargetUpdatesSearchPaths() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "App", at: projectPath,
    )

    // Set search paths that reference the target name
    let xcodeproj = try XcodeProj(path: projectPath)
    let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
    for config in target.buildConfigurationList?.buildConfigurations ?? [] {
      config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] = .array([
        "$(inherited)",
        "@executable_path/../Frameworks/App",
      ])
      config.buildSettings["FRAMEWORK_SEARCH_PATHS"] = .string(
        "$(BUILT_PRODUCTS_DIR)/App/Frameworks",
      )
    }
    try PBXProjWriter.write(xcodeproj, to: projectPath)

    // Rename the target
    let tool = RenameTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
    let result = try tool.execute(arguments: [
      "project_path": Value.string(projectPath.string),
      "target_name": Value.string("App"),
      "new_name": Value.string("NewApp"),
    ])

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully renamed"))

    // Verify search paths updated
    let updatedProj = try XcodeProj(path: projectPath)
    let renamedTarget = try #require(
      updatedProj.pbxproj.nativeTargets.first { $0.name == "NewApp" },
    )
    let config = try #require(
      renamedTarget.buildConfigurationList?.buildConfigurations.first,
    )

    // LD_RUNPATH_SEARCH_PATHS (array value)
    if case .array(let ldPaths) = config.buildSettings["LD_RUNPATH_SEARCH_PATHS"] {
      #expect(ldPaths.contains("@executable_path/../Frameworks/NewApp"))
      #expect(!ldPaths.contains("@executable_path/../Frameworks/App"))
    } else {
      Issue.record("Expected array value for LD_RUNPATH_SEARCH_PATHS")
    }

    // FRAMEWORK_SEARCH_PATHS (string value)
    #expect(
      config.buildSettings["FRAMEWORK_SEARCH_PATHS"]?.stringValue
        == "$(BUILT_PRODUCTS_DIR)/NewApp/Frameworks",
    )
  }
}
