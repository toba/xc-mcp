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
    func `Scaffold wires source files to sources build phase`() throws {
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

        // Find the app target
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil, "App target should exist")

        // Verify sources build phase has the Swift files
        let sourcesBuildPhase =
            target?.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil, "Sources build phase should exist")

        let sourceFileNames = sourcesBuildPhase?.files?.compactMap { $0.file?.name } ?? []
        #expect(
            sourceFileNames.contains("TestAppApp.swift"),
            "Sources should contain TestAppApp.swift, got: \(sourceFileNames)",
        )
        #expect(
            sourceFileNames.contains("ContentView.swift"),
            "Sources should contain ContentView.swift, got: \(sourceFileNames)",
        )
    }

    @Test
    func `Scaffold wires asset catalog to resources build phase`() throws {
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

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil)

        // Verify resources build phase has the asset catalog
        let resourcesBuildPhase =
            target?.buildPhases.first { $0 is PBXResourcesBuildPhase } as? PBXResourcesBuildPhase
        #expect(resourcesBuildPhase != nil, "Resources build phase should exist")

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

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath =
            Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)

        let assetsRef = xcodeproj.pbxproj.fileReferences.first { $0.name == "Assets.xcassets" }
        #expect(assetsRef != nil, "Assets.xcassets file reference should exist")
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

        // Main group should contain the app group
        let appGroup = mainGroup?.children.compactMap { $0 as? PBXGroup }.first {
            $0.name == "TestApp"
        }
        #expect(appGroup != nil, "Main group should contain TestApp group")
        #expect(appGroup?.path == "TestApp", "App group path should be TestApp")

        // App group should contain all file references
        let childNames = appGroup?.children.compactMap { ($0 as? PBXFileReference)?.name } ?? []
        #expect(childNames.contains("TestAppApp.swift"))
        #expect(childNames.contains("ContentView.swift"))
        #expect(childNames.contains("TestApp.entitlements"))
        #expect(childNames.contains("Assets.xcassets"))
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
    func `Scaffold entitlements not in any build phase`() throws {
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

        // Entitlements should NOT appear in any build phase
        let allBuildFileNames = target.buildPhases.flatMap { phase in
            phase.files?.compactMap { $0.file?.name } ?? []
        }
        #expect(
            !allBuildFileNames.contains("TestApp.entitlements"),
            "Entitlements should not be in any build phase",
        )

        // But should exist as a file reference in the project
        let entitlementsRef = xcodeproj.pbxproj.fileReferences.first {
            $0.name == "TestApp.entitlements"
        }
        #expect(entitlementsRef != nil, "Entitlements file reference should exist in project")
    }
}
