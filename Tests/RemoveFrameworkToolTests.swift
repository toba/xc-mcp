import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for missing parameter validation
struct RemoveFrameworkMissingParamTestCase: Sendable {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

@Suite("RemoveFrameworkTool Tests")
struct RemoveFrameworkToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = RemoveFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_framework")
        #expect(toolDefinition.description == "Remove a framework dependency from an Xcode project")
    }

    static let missingParamCases: [RemoveFrameworkMissingParamTestCase] = [
        RemoveFrameworkMissingParamTestCase(
            "Missing project_path",
            [
                "framework_name": Value.string("UIKit"),
            ],
        ),
        RemoveFrameworkMissingParamTestCase(
            "Missing framework_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
            ],
        ),
    ]

    @Test("Remove framework with missing parameter", arguments: missingParamCases)
    func removeFrameworkWithMissingParameters(
        _ testCase: RemoveFrameworkMissingParamTestCase,
    ) throws {
        let tool = RemoveFrameworkTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test("Remove system framework")
    func removeSystemFramework() throws {
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

        let pathUtility = PathUtility(basePath: tempDir.path)

        // Add UIKit first
        let addTool = AddFrameworkTool(pathUtility: pathUtility)
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ])

        // Verify it was added
        let before = try XcodeProj(path: projectPath)
        let beforeTarget = before.pbxproj.nativeTargets.first { $0.name == "App" }
        let beforePhase =
            beforeTarget?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
        #expect(beforePhase?.files?.isEmpty == false)

        // Remove it
        let removeTool = RemoveFrameworkTool(pathUtility: pathUtility)
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("UIKit"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed framework 'UIKit'"))
        #expect(message.contains("App"))

        // Verify framework phase is now empty and file ref is gone
        let after = try XcodeProj(path: projectPath)
        let afterTarget = after.pbxproj.nativeTargets.first { $0.name == "App" }
        let afterPhase =
            afterTarget?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase

        let hasUIKit =
            afterPhase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "UIKit.framework"
                }
                return false
            } ?? false
        #expect(hasUIKit == false)

        // Verify file reference was cleaned up
        let uikitRefs = after.pbxproj.fileReferences.filter {
            $0.name == "UIKit.framework"
        }
        #expect(uikitRefs.isEmpty)
    }

    @Test("Remove embedded custom framework")
    func removeEmbeddedCustomFramework() throws {
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

        let pathUtility = PathUtility(basePath: tempDir.path)

        // Add custom framework with embedding
        let addTool = AddFrameworkTool(pathUtility: pathUtility)
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string(
                tempDir.appendingPathComponent("Custom.framework").path,
            ),
            "embed": Value.bool(true),
        ])

        // Verify embed phase exists
        let before = try XcodeProj(path: projectPath)
        let beforeTarget = before.pbxproj.nativeTargets.first { $0.name == "App" }
        let hasEmbedBefore =
            beforeTarget?.buildPhases.contains { phase in
                if let copyPhase = phase as? PBXCopyFilesBuildPhase,
                   copyPhase.dstSubfolderSpec == .frameworks
                {
                    return copyPhase.files?.isEmpty == false
                }
                return false
            } ?? false
        #expect(hasEmbedBefore == true)

        // Remove
        let removeTool = RemoveFrameworkTool(pathUtility: pathUtility)
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("Custom.framework"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed framework"))

        // Verify both link and embed phases are cleaned
        let after = try XcodeProj(path: projectPath)
        let afterTarget = after.pbxproj.nativeTargets.first { $0.name == "App" }

        let linkPhase =
            afterTarget?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
        let hasCustomInLink =
            linkPhase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "Custom.framework"
                        || fileRef.path?.hasSuffix("Custom.framework") == true
                }
                return false
            } ?? false
        #expect(hasCustomInLink == false)

        let hasCustomInEmbed =
            afterTarget?.buildPhases.contains { phase in
                if let copyPhase = phase as? PBXCopyFilesBuildPhase,
                   copyPhase.dstSubfolderSpec == .frameworks
                {
                    return copyPhase.files?.contains { buildFile in
                        if let fileRef = buildFile.file as? PBXFileReference {
                            return fileRef.name == "Custom.framework"
                                || fileRef.path?.hasSuffix("Custom.framework") == true
                        }
                        return false
                    } ?? false
                }
                return false
            } ?? false
        #expect(hasCustomInEmbed == false)
    }

    @Test("Remove from specific target preserves other targets")
    func removeFromSpecificTarget() throws {
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

        // Add a second target
        let xcodeproj = try XcodeProj(path: projectPath)
        let targetDebugConfig = XCBuildConfiguration(
            name: "Debug", buildSettings: ["PRODUCT_NAME": "App2"],
        )
        let targetReleaseConfig = XCBuildConfiguration(
            name: "Release", buildSettings: ["PRODUCT_NAME": "App2"],
        )
        xcodeproj.pbxproj.add(object: targetDebugConfig)
        xcodeproj.pbxproj.add(object: targetReleaseConfig)
        let targetConfigList = XCConfigurationList(
            buildConfigurations: [targetDebugConfig, targetReleaseConfig],
            defaultConfigurationName: "Release",
        )
        xcodeproj.pbxproj.add(object: targetConfigList)

        let target2 = PBXNativeTarget(
            name: "App2",
            buildConfigurationList: targetConfigList,
            buildPhases: [],
            productType: .application,
        )
        xcodeproj.pbxproj.add(object: target2)
        xcodeproj.pbxproj.rootObject?.targets.append(target2)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let pathUtility = PathUtility(basePath: tempDir.path)

        // Add UIKit to both targets
        let addTool = AddFrameworkTool(pathUtility: pathUtility)
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ])
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App2"),
            "framework_name": Value.string("UIKit"),
        ])

        // Remove from App only
        let removeTool = RemoveFrameworkTool(pathUtility: pathUtility)
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("UIKit"),
            "target_name": Value.string("App"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("App"))
        #expect(!message.contains("App2"))

        // Verify App no longer has UIKit
        let after = try XcodeProj(path: projectPath)
        let appTarget = after.pbxproj.nativeTargets.first { $0.name == "App" }
        let appPhase =
            appTarget?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
        let appHasUIKit =
            appPhase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "UIKit.framework"
                }
                return false
            } ?? false
        #expect(appHasUIKit == false)

        // Verify App2 still has UIKit
        let app2Target = after.pbxproj.nativeTargets.first { $0.name == "App2" }
        let app2Phase =
            app2Target?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                as? PBXFrameworksBuildPhase
        let app2HasUIKit =
            app2Phase?.files?.contains { buildFile in
                if let fileRef = buildFile.file as? PBXFileReference {
                    return fileRef.name == "UIKit.framework"
                }
                return false
            } ?? false
        #expect(app2HasUIKit == true)

        // File reference should still exist (App2 uses it)
        let uikitRefs = after.pbxproj.fileReferences.filter {
            $0.name == "UIKit.framework"
        }
        #expect(!uikitRefs.isEmpty)
    }

    @Test("Remove from all targets when target_name omitted")
    func removeFromAllTargets() throws {
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

        // Add a second target
        let xcodeproj = try XcodeProj(path: projectPath)
        let targetDebugConfig = XCBuildConfiguration(
            name: "Debug", buildSettings: ["PRODUCT_NAME": "App2"],
        )
        let targetReleaseConfig = XCBuildConfiguration(
            name: "Release", buildSettings: ["PRODUCT_NAME": "App2"],
        )
        xcodeproj.pbxproj.add(object: targetDebugConfig)
        xcodeproj.pbxproj.add(object: targetReleaseConfig)
        let targetConfigList = XCConfigurationList(
            buildConfigurations: [targetDebugConfig, targetReleaseConfig],
            defaultConfigurationName: "Release",
        )
        xcodeproj.pbxproj.add(object: targetConfigList)

        let target2 = PBXNativeTarget(
            name: "App2",
            buildConfigurationList: targetConfigList,
            buildPhases: [],
            productType: .application,
        )
        xcodeproj.pbxproj.add(object: target2)
        xcodeproj.pbxproj.rootObject?.targets.append(target2)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let pathUtility = PathUtility(basePath: tempDir.path)

        // Add UIKit to both targets
        let addTool = AddFrameworkTool(pathUtility: pathUtility)
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ])
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App2"),
            "framework_name": Value.string("UIKit"),
        ])

        // Remove from all targets (no target_name)
        let removeTool = RemoveFrameworkTool(pathUtility: pathUtility)
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("UIKit"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("App"))
        #expect(message.contains("App2"))

        // Verify both targets no longer have UIKit
        let after = try XcodeProj(path: projectPath)
        for targetName in ["App", "App2"] {
            let target = after.pbxproj.nativeTargets.first { $0.name == targetName }
            let phase =
                target?.buildPhases.first { $0 is PBXFrameworksBuildPhase }
                    as? PBXFrameworksBuildPhase
            let hasUIKit =
                phase?.files?.contains { buildFile in
                    if let fileRef = buildFile.file as? PBXFileReference {
                        return fileRef.name == "UIKit.framework"
                    }
                    return false
                } ?? false
            #expect(hasUIKit == false)
        }

        // File reference should be cleaned up
        let uikitRefs = after.pbxproj.fileReferences.filter {
            $0.name == "UIKit.framework"
        }
        #expect(uikitRefs.isEmpty)
    }

    @Test("Framework not found returns informative message")
    func frameworkNotFound() throws {
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

        let removeTool = RemoveFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("NonExistent"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Target not found returns informative message")
    func targetNotFound() throws {
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

        let removeTool = RemoveFrameworkTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("UIKit"),
            "target_name": Value.string("NonExistentTarget"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test("Name normalization — add without suffix, remove with suffix")
    func nameNormalization() throws {
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

        let pathUtility = PathUtility(basePath: tempDir.path)

        // Add as "UIKit" (no suffix)
        let addTool = AddFrameworkTool(pathUtility: pathUtility)
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("UIKit"),
        ])

        // Remove as "UIKit.framework" (with suffix)
        let removeTool = RemoveFrameworkTool(pathUtility: pathUtility)
        let result = try removeTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "framework_name": Value.string("UIKit.framework"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed framework"))

        // Verify it's actually gone
        let after = try XcodeProj(path: projectPath)
        let uikitRefs = after.pbxproj.fileReferences.filter {
            $0.name == "UIKit.framework"
        }
        #expect(uikitRefs.isEmpty)
    }
}
