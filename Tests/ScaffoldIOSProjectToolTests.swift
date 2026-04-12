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
    func `Scaffold wires source files to sources build phase`() throws {
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

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil, "App target should exist")

        let sourcesBuildPhase =
            target?.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)

        let sourceFileNames = sourcesBuildPhase?.files?.compactMap { $0.file?.name } ?? []
        #expect(sourceFileNames.contains("TestAppApp.swift"))
        #expect(sourceFileNames.contains("ContentView.swift"))
    }

    @Test
    func `Scaffold wires asset catalog to resources build phase`() throws {
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

        let resourcesBuildPhase =
            target.buildPhases.first { $0 is PBXResourcesBuildPhase } as? PBXResourcesBuildPhase
        #expect(resourcesBuildPhase != nil)

        let resourceFileNames = resourcesBuildPhase?.files?.compactMap { $0.file?.name } ?? []
        #expect(
            resourceFileNames.contains("Assets.xcassets"),
            "Resources should contain Assets.xcassets, got: \(resourceFileNames)",
        )
    }

    @Test
    func `Scaffold sets lastKnownFileType on asset catalog`() throws {
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

        let assetsRef = xcodeproj.pbxproj.fileReferences.first { $0.name == "Assets.xcassets" }
        #expect(assetsRef != nil)
        #expect(
            assetsRef?.lastKnownFileType == "folder.assetcatalog",
            "lastKnownFileType should be folder.assetcatalog, got: \(assetsRef?.lastKnownFileType ?? "nil")",
        )
    }

    @Test
    func `Scaffold creates app group in main group`() throws {
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

        let appGroup = mainGroup?.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "TestApp"
        }
        #expect(appGroup != nil, "Main group should contain TestApp group")

        let childNames = appGroup?.children.compactMap { ($0 as? PBXFileReference)?.name } ?? []
        #expect(childNames.contains("TestAppApp.swift"))
        #expect(childNames.contains("ContentView.swift"))
        #expect(childNames.contains("Assets.xcassets"))
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
