import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ScaffoldIOSProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "scaffold_ios_project")
    }

    @Test
    func `Scaffold uses synchronized root group for app source folder`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath =
            Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)

        let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup
        let syncGroup = mainGroup?.children.compactMap {
            $0 as? PBXFileSystemSynchronizedRootGroup
        }.first { $0.path == "TestApp" }
        #expect(syncGroup != nil, "Main group should contain a synchronized root group for TestApp")

        let appGroup = mainGroup?.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "TestApp"
        }
        #expect(appGroup == nil, "Should not emit a traditional PBXGroup alongside the sync folder")

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target?.fileSystemSynchronizedGroups?.contains { $0 === syncGroup } == true)
    }

    @Test
    func `Scaffold leaves build phases empty under synchronized folder`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath =
            Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }!

        let sourcesBuildPhase =
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)
        #expect(sourcesBuildPhase?.files?.isEmpty ?? true)

        let resourcesBuildPhase =
            target.buildPhases.first { $0 is PBXResourcesBuildPhase } as? PBXResourcesBuildPhase
        #expect(resourcesBuildPhase != nil)
        #expect(resourcesBuildPhase?.files?.isEmpty ?? true)

        let refNames = xcodeproj.pbxproj.fileReferences.compactMap { $0.name }
        #expect(!refNames.contains("TestAppApp.swift"))
        #expect(!refNames.contains("ContentView.swift"))
        #expect(!refNames.contains("Assets.xcassets"))
    }

    @Test
    func `Scaffold generates iOS AppIcon Contents json`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let contentsPath = tempDir.appendingPathComponent(
            "TestApp/TestApp/Assets.xcassets/AppIcon.appiconset/Contents.json",
        )
        let data = try Data(contentsOf: contentsPath)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let images = json["images"] as! [[String: String]]

        // iOS uses single 1024x1024 universal entry
        #expect(images.count == 1, "iOS icon should have 1 entry, got: \(images.count)")
        #expect(images[0]["idiom"] == "universal")
        #expect(images[0]["platform"] == "ios")
        #expect(images[0]["size"] == "1024x1024")
    }
}
