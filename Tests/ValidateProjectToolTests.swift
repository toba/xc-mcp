import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite("ValidateProjectTool Tests")
struct ValidateProjectToolTests {
    @Test("Tool creation")
    func toolCreation() {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "validate_project")
        #expect(toolDefinition.description?.contains("Validate") == true)
    }

    @Test("Missing project_path throws")
    func missingProjectPath() throws {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test("Invalid project path throws")
    func invalidProjectPath() throws {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/nonexistent/path.xcodeproj")])
        }
    }

    @Test("Clean project reports no issues")
    func cleanProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("No issues found"))
    }

    @Test("Detects embed phase with nil dstSubfolderSpec")
    func detectsBrokenEmbedPhase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add an "Embed Frameworks" phase with nil dstSubfolderSpec
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let fileRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Test.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: fileRef)
        let buildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile)

        // Create phase with no dstSubfolderSpec (nil) but named "Embed Frameworks"
        let brokenPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: nil,
            name: "Embed Frameworks",
            files: [buildFile],
        )
        xcodeproj.pbxproj.add(object: brokenPhase)
        target.buildPhases.append(brokenPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[error]"))
        #expect(content.contains("dstSubfolder=None"))
        #expect(content.contains("1 error"))
    }

    @Test("Detects empty copy-files phase")
    func detectsEmptyCopyFilesPhase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let emptyPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
        )
        xcodeproj.pbxproj.add(object: emptyPhase)
        target.buildPhases.append(emptyPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[warn]"))
        #expect(content.contains("zero files"))
    }

    @Test("Detects duplicate framework in multiple phases")
    func detectsDuplicateEmbed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let fileRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Core.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: fileRef)

        // Add same framework to two different copy-files phases
        let buildFile1 = PBXBuildFile(file: fileRef)
        let buildFile2 = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile1)
        xcodeproj.pbxproj.add(object: buildFile2)

        let phase1 = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
            files: [buildFile1],
        )
        let phase2 = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks 2",
            files: [buildFile2],
        )
        xcodeproj.pbxproj.add(object: phase1)
        xcodeproj.pbxproj.add(object: phase2)
        target.buildPhases.append(phase1)
        target.buildPhases.append(phase2)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[error]"))
        #expect(content.contains("appears in both"))
    }

    @Test("Detects linked but not embedded framework")
    func detectsLinkedNotEmbedded() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        // Add framework to link phase only
        let fileRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "MathView.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: fileRef)
        let buildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile)

        let frameworksPhase = PBXFrameworksBuildPhase(files: [buildFile])
        xcodeproj.pbxproj.add(object: frameworksPhase)
        target.buildPhases.append(frameworksPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[warn]"))
        #expect(content.contains("MathView.framework linked but not embedded"))
    }

    @Test("Reports correctly linked and embedded frameworks")
    func reportsMatchedFrameworks() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        let fileRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Core.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: fileRef)

        // Link
        let linkBuildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: linkBuildFile)
        let frameworksPhase = PBXFrameworksBuildPhase(files: [linkBuildFile])
        xcodeproj.pbxproj.add(object: frameworksPhase)
        target.buildPhases.append(frameworksPhase)

        // Embed
        let embedBuildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: embedBuildFile)
        let embedPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
            files: [embedBuildFile],
        )
        xcodeproj.pbxproj.add(object: embedPhase)
        target.buildPhases.append(embedPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("1 framework linked and embedded correctly"))
    }

    @Test("Detects missing target dependency")
    func detectsMissingDependency() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework target
        let xcodeproj = try XcodeProj(path: projectPath)
        let pbxproj = xcodeproj.pbxproj

        let fwkDebugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let fwkReleaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: fwkDebugConfig)
        pbxproj.add(object: fwkReleaseConfig)
        let fwkConfigList = XCConfigurationList(
            buildConfigurations: [fwkDebugConfig, fwkReleaseConfig],
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: fwkConfigList)

        let productRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Core.framework",
            includeInIndex: false,
        )
        pbxproj.add(object: productRef)

        let fwkTarget = PBXNativeTarget(
            name: "Core",
            buildConfigurationList: fwkConfigList,
            buildPhases: [],
            product: productRef,
            productType: .framework,
        )
        pbxproj.add(object: fwkTarget)
        try pbxproj.rootProject()?.targets.append(fwkTarget)

        // Link Core.framework in App but don't add dependency
        let appTarget = try #require(pbxproj.nativeTargets.first { $0.name == "App" })
        let buildFile = PBXBuildFile(file: productRef)
        pbxproj.add(object: buildFile)
        let frameworksPhase = PBXFrameworksBuildPhase(files: [buildFile])
        pbxproj.add(object: frameworksPhase)
        appTarget.buildPhases.append(frameworksPhase)

        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Links Core.framework from Core but has no target dependency"))
    }
}
