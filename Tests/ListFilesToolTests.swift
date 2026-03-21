import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListFilesToolTests {
    @Test func `list files tool creation`() {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "list_files")
        #expect(
            toolDefinition.description == "List all files in a specific target of an Xcode project",
        )
    }

    @Test func `list files with missing parameters`() throws {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("test.xcodeproj")])
        }
    }

    @Test func `list files with invalid project path`() throws {
        let tool = ListFilesTool(pathUtility: PathUtility(basePath: "/workspace"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
            "target_name": Value.string("TestTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test func `list files with empty target`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        // List files in the target
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("TestProject"))
            #expect(content.contains("No files found"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func `list files with invalid target`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        // List files with invalid target name
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: listArguments)
        }
    }

    @Test func `list files with source files`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target using XcodeProj
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        // Add a source file to the project
        let sourceFilePath = tempDir.path + "/TestFile.swift"
        try "// Test file content".write(
            to: URL(filePath: sourceFilePath), atomically: true, encoding: .utf8,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first)
        let fileReference = PBXFileReference(
            sourceTree: .group, name: "TestFile.swift", path: "TestFile.swift",
        )
        xcodeproj.pbxproj.add(object: fileReference)

        let buildFile = PBXBuildFile(file: fileReference)
        xcodeproj.pbxproj.add(object: buildFile)

        if let sourcesBuildPhase = target.buildPhases.first(where: { $0 is PBXSourcesBuildPhase })
            as? PBXSourcesBuildPhase
        {
            sourcesBuildPhase.files?.append(buildFile)
        }

        try xcodeproj.write(path: projectPath)

        // List files in the target
        let listArguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ]

        let result = try tool.execute(arguments: listArguments)

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("TestFile.swift"))
            #expect(content.contains("Sources:"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func `list files with synchronized folder`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first)
        let mainGroup = try #require(xcodeproj.pbxproj.rootObject?.mainGroup)

        // Add a synchronized root group
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "App/Sources",
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        mainGroup.children.append(syncGroup)
        target.fileSystemSynchronizedGroups = [syncGroup]

        try xcodeproj.write(path: projectPath)

        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Synchronized folders:"))
            #expect(content.contains("App/Sources"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func `list files with synchronized folder exceptions`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first)
        let mainGroup = try #require(xcodeproj.pbxproj.rootObject?.mainGroup)

        // Add a synchronized root group with exceptions
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "App/Sources",
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        mainGroup.children.append(syncGroup)
        target.fileSystemSynchronizedGroups = [syncGroup]

        let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
            target: target,
            membershipExceptions: ["Excluded.swift", "TestHelper.swift"],
            publicHeaders: nil,
            privateHeaders: nil,
            additionalCompilerFlagsByRelativePath: nil,
            attributesByRelativePath: nil,
        )
        xcodeproj.pbxproj.add(object: exceptionSet)
        syncGroup.exceptions = [exceptionSet]

        try xcodeproj.write(path: projectPath)

        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Synchronized folders:"))
            #expect(content.contains("App/Sources"))
            #expect(content.contains("membership exceptions — not compiled:"))
            #expect(content.contains("Excluded.swift"))
            #expect(content.contains("TestHelper.swift"))
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test func `list files with sync group via exception set`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = ListFilesTool(pathUtility: PathUtility(basePath: tempDir.path))

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestProject", at: projectPath,
        )

        // Create a synchronized folder on disk with some Swift files
        let syncFolderPath = tempDir.appendingPathComponent("SyncFolder")
        try FileManager.default.createDirectory(
            at: syncFolderPath,
            withIntermediateDirectories: true,
        )
        try "// A".write(
            to: syncFolderPath.appendingPathComponent("FileA.swift"),
            atomically: true, encoding: .utf8,
        )
        try "// B".write(
            to: syncFolderPath.appendingPathComponent("FileB.swift"),
            atomically: true, encoding: .utf8,
        )
        try "// C".write(
            to: syncFolderPath.appendingPathComponent("Included.swift"),
            atomically: true, encoding: .utf8,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first)
        let mainGroup = try #require(xcodeproj.pbxproj.rootObject?.mainGroup)

        // Add a synchronized root group NOT on target.fileSystemSynchronizedGroups
        // but associated via an exception set referencing the target.
        // In this case membershipExceptions lists files that ARE compiled (included).
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "SyncFolder",
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        mainGroup.children.append(syncGroup)
        // Do NOT set target.fileSystemSynchronizedGroups — exception-only association

        let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
            target: target,
            membershipExceptions: ["Included.swift"],
            publicHeaders: nil,
            privateHeaders: nil,
            additionalCompilerFlagsByRelativePath: nil,
            attributesByRelativePath: nil,
        )
        xcodeproj.pbxproj.add(object: exceptionSet)
        syncGroup.exceptions = [exceptionSet]

        try xcodeproj.write(path: projectPath)

        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestProject"),
        ])

        #expect(result.content.count == 1)
        if case let .text(content) = result.content[0] {
            #expect(content.contains("Synchronized folders:"))
            #expect(content.contains("SyncFolder"))
            // Exception-only: membershipExceptions = files compiled as exceptions
            #expect(content.contains("membership exceptions — compiled as exceptions:"))
            #expect(content.contains("Included.swift"))
            // Only the exception file should appear in the compiled listing
            #expect(content.contains("Compiled files (via exceptions)"))
            // FileA and FileB are NOT compiled (target doesn't own the folder)
            let parts = content.components(separatedBy: "Compiled files (via exceptions)")
            if parts.count > 1 {
                let fileListing = parts[1]
                #expect(fileListing.contains("Included.swift"))
                #expect(!fileListing.contains("FileA.swift"))
                #expect(!fileListing.contains("FileB.swift"))
            }
        } else {
            Issue.record("Expected text content")
        }
    }
}
