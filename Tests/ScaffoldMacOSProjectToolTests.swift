import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct ScaffoldMacOSProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "scaffold_macos_project")
    }

    @Test
    func `Scaffold creates buildable project structure`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectDir = tempDir.appendingPathComponent("TestApp")

        // Verify files exist on disk
        #expect(FileManager.default.fileExists(
            atPath: projectDir.appendingPathComponent("TestApp.xcodeproj").path,
        ),
        )
        #expect(FileManager.default.fileExists(
            atPath: projectDir.appendingPathComponent("TestApp/TestAppApp.swift").path,
        ),
        )
        #expect(FileManager.default.fileExists(
            atPath: projectDir.appendingPathComponent("TestApp/ContentView.swift").path,
        ),
        )
        #expect(FileManager.default.fileExists(
            atPath: projectDir.appendingPathComponent("TestApp/Assets.xcassets/Contents.json")
                .path,
        ),
        )
    }

    @Test
    func `Scaffold uses synchronized root group for app source folder`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath = Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)

        let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup
        let syncGroup = mainGroup?.children.lazy
            .compactMap { $0 as? PBXFileSystemSynchronizedRootGroup }
            .first { $0.path == "TestApp" }
        #expect(syncGroup != nil, "Main group should contain a synchronized root group for TestApp")

        // No traditional PBXGroup for the app folder
        let appGroup = mainGroup?.children.lazy.compactMap { $0 as? PBXGroup }.first {
            $0.name == "TestApp"
        }
        #expect(appGroup == nil, "Should not emit a traditional PBXGroup alongside the sync folder")

        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target?.fileSystemSynchronizedGroups?.contains { $0 === syncGroup } == true)
    }

    @Test
    func `Scaffold leaves build phases empty under synchronized folder`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath = Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" })

        // Sources/Resources phases exist but contribute no explicit files — the synchronized folder
        // feeds them at build time.
        let sourcesBuildPhase = target.buildPhases.first { $0 is PBXSourcesBuildPhase }
            as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)
        #expect(sourcesBuildPhase?.files?.isEmpty ?? true)

        let resourcesBuildPhase = target.buildPhases.first { $0 is PBXResourcesBuildPhase }
            as? PBXResourcesBuildPhase
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
        let tempDir = TemporaryDirectory.url

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
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: String]])

        // Every image entry must have a "scale" key
        for image in images {
            #expect(image["scale"] != nil, "Image entry missing 'scale': \(image)")
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
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        // Entitlements live on disk inside the synchronized folder; Xcode resolves them via
        // CODE_SIGN_ENTITLEMENTS without needing a build-phase entry.
        let entitlementsPath = tempDir.appendingPathComponent(
            "TestApp/TestApp/TestApp.entitlements",
        )
        #expect(FileManager.default.fileExists(atPath: entitlementsPath.path))
    }

    @Test
    func `Development team goes into a git-ignored Local xcconfig`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
            "development_team": Value.string("ABCDE12345"),
        ])

        let projectDir = tempDir.appendingPathComponent("TestApp")
        let shared = try String(
            contentsOf: projectDir.appendingPathComponent("Config/Shared.xcconfig"), encoding: .utf8,
        )
        #expect(shared.contains("#include? \"Local.xcconfig\""))

        let local = try String(
            contentsOf: projectDir.appendingPathComponent("Config/Local.xcconfig"), encoding: .utf8,
        )
        #expect(local.contains("DEVELOPMENT_TEAM = ABCDE12345"))

        let gitignore = try String(
            contentsOf: projectDir.appendingPathComponent(".gitignore"), encoding: .utf8,
        )
        #expect(gitignore.split(separator: "\n").contains("Config/Local.xcconfig"))

        let xcodeproj = try XcodeProj(path: Path(projectDir.path) + "TestApp.xcodeproj")
        let projectConfigs = try #require(
            xcodeproj.pbxproj.rootProject()?.buildConfigurationList?.buildConfigurations,
        )
        #expect(projectConfigs.count == 2)

        for config in projectConfigs {
            let base = try #require(config.baseConfiguration)
            let fullPath = try base.fullPath(sourceRoot: projectDir.path)
            #expect(fullPath == projectDir.appendingPathComponent("Config/Shared.xcconfig").path)
        }

        let pbxprojText = try String(
            contentsOf: projectDir.appendingPathComponent("TestApp.xcodeproj/project.pbxproj"),
            encoding: .utf8,
        )
        #expect(!pbxprojText.contains("DEVELOPMENT_TEAM"))
        #expect(!pbxprojText.contains("Local.xcconfig"))
    }

    @Test
    func `Scaffold without development team writes no xcconfig`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectDir = tempDir.appendingPathComponent("TestApp")
        #expect(
            !FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent("Config").path,
            ))
        #expect(
            !FileManager.default.fileExists(
                atPath: projectDir.appendingPathComponent(".gitignore").path,
            ))

        let xcodeproj = try XcodeProj(path: Path(projectDir.path) + "TestApp.xcodeproj")
        let configs = xcodeproj.pbxproj.buildConfigurations
        #expect(configs.allSatisfy { $0.baseConfiguration == nil })
    }

    @Test(arguments: ["", "ABC DE", "ABC\nOTHER = 1"])
    func `Scaffold rejects a malformed development team`(team: String) throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldMacOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_name": Value.string("TestApp"),
                "path": Value.string(tempDir.path),
                "development_team": Value.string(team),
            ])
        }
        #expect(
            !FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("TestApp").path))
    }
}
