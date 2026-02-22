import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for missing parameter validation
struct SetBuildSettingMissingParamTestCase: Sendable {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

@Suite("SetBuildSettingTool Tests")
struct SetBuildSettingToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_build_setting")
        #expect(toolDefinition.description == "Modify build settings for a target")
    }

    static let missingParamCases: [SetBuildSettingMissingParamTestCase] = [
        SetBuildSettingMissingParamTestCase(
            "Missing project_path",
            [
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ],
        ),
        SetBuildSettingMissingParamTestCase(
            "Missing target_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ],
        ),
        SetBuildSettingMissingParamTestCase(
            "Missing configuration",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("5.0"),
            ],
        ),
        SetBuildSettingMissingParamTestCase(
            "Missing setting_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_value": Value.string("5.0"),
            ],
        ),
        SetBuildSettingMissingParamTestCase(
            "Missing setting_value",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
            ],
        ),
    ]

    @Test("Set build setting with missing parameter", arguments: missingParamCases)
    func setBuildSettingWithMissingParameters(_ testCase: SetBuildSettingMissingParamTestCase)
        throws
    {
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test("Set build setting for specific configuration")
    func setBuildSettingForSpecificConfiguration() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Set build setting
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully set 'SWIFT_VERSION' to '5.9'"))
        #expect(message.contains("Debug"))

        // Verify setting was changed
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let debugConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        #expect(debugConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")

        // Verify Release config was not changed
        let releaseConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Release"
        }
        #expect(releaseConfig?.buildSettings["SWIFT_VERSION"]?.stringValue != "5.9")
    }

    @Test("Set build setting for all configurations")
    func setBuildSettingForAllConfigurations() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Set build setting for all configurations
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("All"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully set 'SWIFT_VERSION' to '5.9'"))
        #expect(message.contains("Debug"))
        #expect(message.contains("Release"))

        // Verify setting was changed in all configurations
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        let debugConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        let releaseConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Release"
        }

        #expect(debugConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")
        #expect(releaseConfig?.buildSettings["SWIFT_VERSION"]?.stringValue == "5.9")
    }

    @Test("Set build setting with non-existent target")
    func setBuildSettingWithNonExistentTarget() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("set_build_setting preserves dstSubfolderSpec on PBXCopyFilesBuildPhase")
    func setBuildSettingPreservesCopyFilesPhase() throws {
        // Regression test for xc-mcp-qem0:
        // set_build_setting drops dstSubfolder fields from PBXCopyFilesBuildPhase sections

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

        // Add a copy files build phase with dstSubfolderSpec = .resources
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let copyPhase = PBXCopyFilesBuildPhase(
            dstPath: "styles",
            dstSubfolderSpec: .resources,
            name: "Copy Styles",
        )
        xcodeproj.pbxproj.add(object: copyPhase)
        target.buildPhases.append(copyPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Verify the phase was created correctly
        let verifyProject = try XcodeProj(path: projectPath)
        let verifyTarget = try #require(
            verifyProject.pbxproj.nativeTargets.first { $0.name == "App" },
        )
        let verifyCopyPhase = verifyTarget.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Styles" }
        #expect(verifyCopyPhase?.dstSubfolderSpec == .resources)
        #expect(verifyCopyPhase?.dstPath == "styles")

        // Now use set_build_setting to change a build setting
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ])

        // Verify the copy files phase still has the correct dstSubfolderSpec
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(
            updatedProject.pbxproj.nativeTargets.first { $0.name == "App" },
        )
        let updatedCopyPhase = updatedTarget.buildPhases
            .compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.name == "Copy Styles" }

        #expect(updatedCopyPhase != nil, "Copy phase should still exist after set_build_setting")
        #expect(
            updatedCopyPhase?.dstSubfolderSpec == .resources,
            "dstSubfolderSpec should remain .resources after set_build_setting (was \(String(describing: updatedCopyPhase?.dstSubfolderSpec)))",
        )
        #expect(
            updatedCopyPhase?.dstPath == "styles",
            "dstPath should remain 'styles' after set_build_setting",
        )
    }

    @Test("set_build_setting preserves Xcode 26 string-based dstSubfolder on round-trip")
    func setBuildSettingPreservesXcode26DstSubfolder() throws {
        // Regression test for tuist/XcodeProj#1034:
        // Xcode 26 writes `dstSubfolder = Resources;` (string) instead of
        // `dstSubfolderSpec = 7;` (numeric). XcodeProj drops the string variant.

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a project normally first, then patch the pbxproj to use Xcode 26 format
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Read the pbxproj and inject a PBXCopyFilesBuildPhase with string-based dstSubfolder
        let pbxprojPath = projectPath + "project.pbxproj"
        var content = try String(contentsOfFile: pbxprojPath.string, encoding: .utf8)

        // Insert a CopyFiles phase using Xcode 26 string format (dstSubfolder, not dstSubfolderSpec)
        let copyPhaseID = "AABBCCDD00112233EEFF4455"
        let copyPhaseBlock = """
        /* Begin PBXCopyFilesBuildPhase section */
        \t\t\(copyPhaseID) /* Copy Styles */ = {
        \t\t\tisa = PBXCopyFilesBuildPhase;
        \t\t\tdstPath = styles;
        \t\t\tdstSubfolder = Resources;
        \t\t\tfiles = (
        \t\t\t);
        \t\t\tname = "Copy Styles";
        \t\t};
        /* End PBXCopyFilesBuildPhase section */

        """

        // Insert the section before PBXFileReference or before PBXGroup
        if content.contains("/* Begin PBXFileReference section */") {
            content = content.replacingOccurrences(
                of: "/* Begin PBXFileReference section */",
                with: copyPhaseBlock + "/* Begin PBXFileReference section */",
            )
        } else {
            content = content.replacingOccurrences(
                of: "/* Begin PBXGroup section */",
                with: copyPhaseBlock + "/* Begin PBXGroup section */",
            )
        }

        // Add the copy phase ref to buildPhases array
        if let buildPhasesRange = content.range(of: "buildPhases = (") {
            let searchStart = buildPhasesRange.upperBound
            if let closingRange = content.range(
                of: "\n\t\t\t);", range: searchStart ..< content.endIndex,
            ) {
                content.insert(
                    contentsOf: "\n\t\t\t\t\(copyPhaseID) /* Copy Styles */,",
                    at: closingRange.lowerBound,
                )
            }
        }

        try content.write(toFile: pbxprojPath.string, atomically: true, encoding: .utf8)

        // Verify the raw file has dstSubfolder (not dstSubfolderSpec)
        let beforeContent = try String(contentsOfFile: pbxprojPath.string, encoding: .utf8)
        #expect(beforeContent.contains("dstSubfolder = Resources;"))
        #expect(!beforeContent.contains("dstSubfolderSpec"))

        // Now use set_build_setting — this triggers PBXProjWriter
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ])

        // Verify dstSubfolder = Resources; is preserved in the written file
        let afterContent = try String(contentsOfFile: pbxprojPath.string, encoding: .utf8)
        #expect(
            afterContent.contains("dstSubfolder = Resources;"),
            "dstSubfolder = Resources should be preserved after set_build_setting round-trip",
        )
    }

    @Test("Set build setting with non-existent configuration")
    func setBuildSettingWithNonExistentConfiguration() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Production"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("5.9"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Configuration 'Production' not found"))
    }
}
