import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ScaffoldMacOSProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "scaffold_macos_project")
    }

    @Test
    func `Scaffold creates buildable project structure`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectDir = tempDir.appendingPathComponent("TestApp")

        // Verify files exist on disk
        #expect(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("TestApp.xcodeproj").path,
            ),
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("TestApp/TestAppApp.swift").path,
            ),
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("TestApp/ContentView.swift").path,
            ),
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("TestApp/Assets.xcassets/Contents.json")
                    .path,
            ),
        )
    }

    @Test
    func `Scaffold uses synchronized root group for app source folder`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
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

        // No traditional PBXGroup for the app folder
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

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath =
            Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }!

        // Sources/Resources phases exist but contribute no explicit files —
        // the synchronized folder feeds them at build time.
        let sourcesBuildPhase =
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)
        #expect(sourcesBuildPhase?.files?.isEmpty ?? true)

        let resourcesBuildPhase =
            target.buildPhases.first { $0 is PBXResourcesBuildPhase } as? PBXResourcesBuildPhase
        #expect(resourcesBuildPhase != nil)
        #expect(resourcesBuildPhase?.files?.isEmpty ?? true)

        // No stray PBXFileReference for sources/assets/entitlements.
        let refNames = xcodeproj.pbxproj.fileReferences.compactMap { $0.name }
        #expect(!refNames.contains("TestAppApp.swift"))
        #expect(!refNames.contains("ContentView.swift"))
        #expect(!refNames.contains("Assets.xcassets"))
        #expect(!refNames.contains("TestApp.entitlements"))
    }

    @Test
    func `Scaffold generates AppIcon Contents json with scale field`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        // Read the AppIcon Contents.json
        let contentsPath = tempDir.appendingPathComponent(
            "TestApp/TestApp/Assets.xcassets/AppIcon.appiconset/Contents.json",
        )
        let data = try Data(contentsOf: contentsPath)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let images = json["images"] as! [[String: String]]

        // Every image entry must have a "scale" key
        for image in images {
            #expect(
                image["scale"] != nil,
                "Image entry missing 'scale': \(image)",
            )
            #expect(
                image["idiom"] == "mac",
                "macOS icon idiom should be 'mac', got: \(image["idiom"] ?? "nil")",
            )
        }

        // Should have 10 entries (5 sizes x 2 scales)
        #expect(images.count == 10, "macOS icon should have 10 entries, got: \(images.count)")
    }

    @Test
    func `Scaffold writes entitlements file alongside source folder`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        // Entitlements live on disk inside the synchronized folder; Xcode
        // resolves them via CODE_SIGN_ENTITLEMENTS without needing a build-phase entry.
        let entitlementsPath = tempDir.appendingPathComponent(
            "TestApp/TestApp/TestApp.entitlements",
        )
        #expect(FileManager.default.fileExists(atPath: entitlementsPath.path))
    }
}
