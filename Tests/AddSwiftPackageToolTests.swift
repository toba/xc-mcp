import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

/// Test case for package requirement tests
struct PackageRequirementTestCase: Sendable {
  let packageUrl: String
  let requirementInput: String
  let expectedRequirementDescription: String

  init(_ packageUrl: String, _ requirementInput: String, _ expectedDescription: String) {
    self.packageUrl = packageUrl
    self.requirementInput = requirementInput
    expectedRequirementDescription = expectedDescription
  }
}

/// Test case for missing parameter validation
struct SwiftPackageMissingParamTestCase: Sendable {
  let description: String
  let arguments: [String: Value]

  init(_ description: String, _ arguments: [String: Value]) {
    self.description = description
    self.arguments = arguments
  }
}

@Suite("AddSwiftPackageTool Tests")
struct AddSwiftPackageToolTests {
  @Test("Tool creation")
  func toolCreation() {
    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))
    let toolDefinition = tool.tool()

    #expect(toolDefinition.name == "add_swift_package")
    #expect(toolDefinition.description == "Add a Swift Package dependency to an Xcode project")
  }

  static let missingParamCases: [SwiftPackageMissingParamTestCase] = [
    SwiftPackageMissingParamTestCase(
      "Missing project_path",
      [
        "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
        "requirement": Value.string("5.0.0"),
      ],
    ),
    SwiftPackageMissingParamTestCase(
      "Missing package_url",
      [
        "project_path": Value.string("/path/to/project.xcodeproj"),
        "requirement": Value.string("5.0.0"),
      ],
    ),
    SwiftPackageMissingParamTestCase(
      "Missing requirement",
      [
        "project_path": Value.string("/path/to/project.xcodeproj"),
        "package_url": Value.string("https://github.com/alamofire/alamofire.git"),
      ],
    ),
  ]

  @Test("Add package with missing parameters", arguments: missingParamCases)
  func addPackageWithMissingParameters(_ testCase: SwiftPackageMissingParamTestCase) throws {
    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: "/tmp"))

    #expect(throws: MCPError.self) {
      try tool.execute(arguments: testCase.arguments)
    }
  }

  static let requirementCases: [PackageRequirementTestCase] = [
    PackageRequirementTestCase(
      "https://github.com/alamofire/alamofire.git",
      "5.0.0",
      #"exact("5.0.0")"#,
    ),
    PackageRequirementTestCase(
      "https://github.com/pointfreeco/swift-composable-architecture.git",
      "from: 1.0.0",
      #"upToNextMajorVersion("1.0.0")"#,
    ),
    PackageRequirementTestCase(
      "https://github.com/apple/swift-algorithms.git",
      "branch: main",
      #"branch("main")"#,
    ),
  ]

  @Test("Add Swift Package with requirement", arguments: requirementCases)
  func addSwiftPackageWithRequirement(_ testCase: PackageRequirementTestCase) throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "package_url": Value.string(testCase.packageUrl),
      "requirement": Value.string(testCase.requirementInput),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully added Swift Package"))

    // Verify package was added
    let xcodeproj = try XcodeProj(path: projectPath)
    let project = try xcodeproj.pbxproj.rootProject()
    let packageRef = project?.remotePackages.first {
      $0.repositoryURL == testCase.packageUrl
    }
    #expect(packageRef != nil)

    // Verify the requirement matches expected description
    if let requirement = packageRef?.versionRequirement {
      let requirementDescription = String(describing: requirement)
      #expect(requirementDescription == testCase.expectedRequirementDescription)
    } else {
      Issue.record("Expected version requirement")
    }
  }

  @Test("Add Swift Package to specific target")
  func addSwiftPackageToSpecificTarget() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "TestApp", at: projectPath,
    )

    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "package_url": Value.string("https://github.com/realm/realm-swift.git"),
      "requirement": Value.string("10.0.0"),
      "target_name": Value.string("TestApp"),
      "product_name": Value.string("RealmSwift"),
    ]

    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("Successfully added Swift Package"))
    #expect(message.contains("to target 'TestApp'"))

    // Verify package was added and linked to target
    let xcodeproj = try XcodeProj(path: projectPath)
    let project = try xcodeproj.pbxproj.rootProject()
    let packageRef = project?.remotePackages.first {
      $0.repositoryURL == "https://github.com/realm/realm-swift.git"
    }
    #expect(packageRef != nil)

    let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
    #expect(target != nil)
    #expect(target?.packageProductDependencies?.count == 1)
  }

  @Test("Add duplicate Swift Package")
  func addDuplicateSwiftPackage() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "package_url": Value.string("https://github.com/apple/swift-collections.git"),
      "requirement": Value.string("1.0.0"),
    ]

    // Add package first time
    _ = try tool.execute(arguments: args)

    // Try to add same package again
    let result = try tool.execute(arguments: args)

    guard case .text(let message) = result.content.first else {
      Issue.record("Expected text result")
      return
    }
    #expect(message.contains("already exists"))
  }

  @Test("Add package with invalid target")
  func addPackageWithInvalidTarget() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
    )
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

    let tool = AddSwiftPackageTool(pathUtility: PathUtility(basePath: tempDir.path))
    let args: [String: Value] = [
      "project_path": Value.string(projectPath.string),
      "package_url": Value.string("https://github.com/apple/swift-collections.git"),
      "requirement": Value.string("1.0.0"),
      "target_name": Value.string("NonExistentTarget"),
    ]

    #expect(throws: MCPError.self) {
      try tool.execute(arguments: args)
    }
  }
}
