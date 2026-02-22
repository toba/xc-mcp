import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

@Suite("ListSynchronizedFolderExceptionsTool Tests")
struct ListSynchronizedFolderExceptionsToolTests {
  let tempDir: String
  let pathUtility: PathUtility

  init() {
    tempDir =
      FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "ListSyncFolderExceptionsToolTests-\(UUID().uuidString)",
      )
      .path
    pathUtility = PathUtility(basePath: tempDir)
    try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
  }

  @Test("Tool has correct properties")
  func toolProperties() {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    #expect(tool.tool().name == "list_synchronized_folder_exceptions")

    let schema = tool.tool().inputSchema
    if case .object(let schemaDict) = schema {
      if case .object(let props) = schemaDict["properties"] {
        #expect(props["project_path"] != nil)
        #expect(props["folder_path"] != nil)
      }

      if case .array(let required) = schemaDict["required"] {
        #expect(required.count == 2)
      }
    }
  }

  @Test("Validates required parameters")
  func validateRequiredParameters() throws {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "project_path": .string("test.xcodeproj")
      ])
    }
  }

  @Test("Returns empty message when no exceptions")
  func returnsEmptyWhenNoExceptions() throws {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    let projectPath = Path(tempDir) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithSyncFolder(
      name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
      at: projectPath,
    )

    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "folder_path": .string("Sources"),
    ])

    if case .text(let message) = result.content.first {
      #expect(message.contains("No exception sets"))
    } else {
      Issue.record("Expected text result")
    }
  }

  @Test("Lists exception sets with files")
  func listsExceptionSetsWithFiles() throws {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    let projectPath = Path(tempDir) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithSyncFolder(
      name: "TestProject", targetName: "AppTarget", folderPath: "Sources",
      membershipExceptions: ["File1.swift", "File2.swift"], at: projectPath,
    )

    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "folder_path": .string("Sources"),
    ])

    if case .text(let message) = result.content.first {
      #expect(message.contains("Target: AppTarget"))
      #expect(message.contains("File1.swift"))
      #expect(message.contains("File2.swift"))
      #expect(message.contains("Membership exceptions"))
    } else {
      Issue.record("Expected text result")
    }
  }

  @Test("Lists multiple exception sets")
  func listsMultipleExceptionSets() throws {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    let projectPath = Path(tempDir) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "AppTarget", at: projectPath,
    )

    // Add a second target
    let xcodeproj = try XcodeProj(path: projectPath)
    let project = try #require(try xcodeproj.pbxproj.rootProject())
    let secondTarget = try PBXNativeTarget(
      name: "TestTarget", buildConfigurationList: #require(project.buildConfigurationList),
    )
    xcodeproj.pbxproj.add(object: secondTarget)
    project.targets.append(secondTarget)

    let syncGroup = PBXFileSystemSynchronizedRootGroup(
      sourceTree: .group, path: "Sources", name: "Sources",
    )
    xcodeproj.pbxproj.add(object: syncGroup)
    if let mainGroup = project.mainGroup {
      mainGroup.children.append(syncGroup)
    }

    let target1 = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" })
    let exception1 = PBXFileSystemSynchronizedBuildFileExceptionSet(
      target: target1,
      membershipExceptions: ["File1.swift"],
      publicHeaders: nil,
      privateHeaders: nil,
      additionalCompilerFlagsByRelativePath: nil,
      attributesByRelativePath: nil,
    )
    xcodeproj.pbxproj.add(object: exception1)

    let exception2 = PBXFileSystemSynchronizedBuildFileExceptionSet(
      target: secondTarget,
      membershipExceptions: ["File2.swift"],
      publicHeaders: nil,
      privateHeaders: nil,
      additionalCompilerFlagsByRelativePath: nil,
      attributesByRelativePath: nil,
    )
    xcodeproj.pbxproj.add(object: exception2)

    syncGroup.exceptions = [exception1, exception2]
    try xcodeproj.write(path: projectPath)

    let result = try tool.execute(arguments: [
      "project_path": .string(projectPath.string),
      "folder_path": .string("Sources"),
    ])

    if case .text(let message) = result.content.first {
      #expect(message.contains("Target: AppTarget"))
      #expect(message.contains("Target: TestTarget"))
      #expect(message.contains("File1.swift"))
      #expect(message.contains("File2.swift"))
    } else {
      Issue.record("Expected text result")
    }
  }

  @Test("Fails when sync folder not found")
  func failsWhenSyncFolderNotFound() throws {
    let tool = ListSynchronizedFolderExceptionsTool(pathUtility: pathUtility)

    let projectPath = Path(tempDir) + "TestProject.xcodeproj"
    try TestProjectHelper.createTestProjectWithTarget(
      name: "TestProject", targetName: "AppTarget", at: projectPath,
    )

    #expect(throws: MCPError.self) {
      try tool.execute(arguments: [
        "project_path": .string(projectPath.string),
        "folder_path": .string("NonExistent"),
      ])
    }
  }
}
