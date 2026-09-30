import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct ScaffoldIOSProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "scaffold_ios_project")
    }

    @Test
    func `Development team goes into a git-ignored Local xcconfig`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
            "development_team": Value.string("ABCDE12345"),
        ])

        let projectDir = tempDir.appendingPathComponent("TestApp")
        let local = try String(
            contentsOf: projectDir.appendingPathComponent("Config/Local.xcconfig"), encoding: .utf8,
        )
        #expect(local.contains("DEVELOPMENT_TEAM = ABCDE12345"))

        let xcodeproj = try XcodeProj(path: Path(projectDir.path) + "TestApp.xcodeproj")
        let projectConfigs = try #require(
            xcodeproj.pbxproj.rootProject()?.buildConfigurationList?.buildConfigurations,
        )
        #expect(projectConfigs.allSatisfy { $0.baseConfiguration?.path == "Shared.xcconfig" })
    }

    @Test
    func `Scaffold uses synchronized root group for app source folder`() throws {
        let tempDir = TemporaryDirectory.url

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
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

        let tool = ScaffoldIOSProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_name": Value.string("TestApp"),
            "path": Value.string(tempDir.path),
            "include_tests": Value.bool(false),
        ])

        let projectPath = Path(tempDir.path) + "TestApp" + "TestApp.xcodeproj"
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" })

        let sourcesBuildPhase = target.buildPhases.first { $0 is PBXSourcesBuildPhase }
            as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)
        #expect(sourcesBuildPhase?.files?.isEmpty ?? true)

        let resourcesBuildPhase = target.buildPhases.first { $0 is PBXResourcesBuildPhase }
            as? PBXResourcesBuildPhase
        #expect(resourcesBuildPhase != nil)
        #expect(resourcesBuildPhase?.files?.isEmpty ?? true)

        let refNames = xcodeproj.pbxproj.fileReferences.compactMap { $0.name }
        #expect(!refNames.contains("TestAppApp.swift"))
        #expect(!refNames.contains("ContentView.swift"))
        #expect(!refNames.contains("Assets.xcassets"))
    }

    @Test
    func `Scaffold generates iOS AppIcon Contents json`() throws {
        let tempDir = TemporaryDirectory.url

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
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try #require(json["images"] as? [[String: String]])

        // iOS uses single 1024x1024 universal entry
        #expect(images.count == 1, "iOS icon should have 1 entry, got: \(images.count)")
        #expect(images[0]["idiom"] == "universal")
        #expect(images[0]["platform"] == "ios")
        #expect(images[0]["size"] == "1024x1024")
    }
}
