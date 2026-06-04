import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct SetFrameworkMergeAttributeToolTests {
    @Test
    func `Tool creation`() {
        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_framework_merge_attribute")
        #expect(toolDefinition.description?.contains("Merge") == true)
    }

    @Test
    func `Missing required params throws`() throws {
        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "framework_name": Value.string("MyLib"),
                "merge": Value.bool(true),
            ])
        }
    }

    /// Sets up a project with a frameworks phase containing one fileRef-based framework.
    private static func makeProjectWithFramework(
        at dir: URL,
        frameworkPath: String = "MyLib.framework",
    ) throws -> (Path, PBXFileReference) {
        let projectPath = Path(dir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!

        let fileRef = PBXFileReference(
            sourceTree: .group,
            name: nil,
            path: frameworkPath,
        )
        xcodeproj.pbxproj.add(object: fileRef)

        let buildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile)

        let frameworksPhase = PBXFrameworksBuildPhase(files: [buildFile])
        xcodeproj.pbxproj.add(object: frameworksPhase)
        target.buildPhases.append(frameworksPhase)

        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())
        return (projectPath, fileRef)
    }

    @Test
    func `Set merge true adds ATTRIBUTES Merge`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyLib.framework"),
            "merge": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("merge=true"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        let phase = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
        let buildFile = phase.files!.first!
        if case let .array(attrs) = buildFile.settings?["ATTRIBUTES"] {
            #expect(attrs.contains("Merge"))
        } else {
            Issue.record("Expected ATTRIBUTES array with 'Merge'")
        }
    }

    @Test
    func `Set merge false removes Merge but keeps other attributes`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)

        // Pre-seed ATTRIBUTES = (Weak, Merge)
        do {
            let xcodeproj = try XcodeProj(path: projectPath)
            let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
            let phase = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
            phase.files!.first!.settings = ["ATTRIBUTES": .array(["Weak", "Merge"])]
            try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())
        }

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyLib.framework"),
            "merge": Value.bool(false),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        let phase = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
        let buildFile = phase.files!.first!
        if case let .array(attrs) = buildFile.settings?["ATTRIBUTES"] {
            #expect(!attrs.contains("Merge"))
            #expect(attrs.contains("Weak"))
        } else {
            Issue.record("Expected ATTRIBUTES array preserving 'Weak'")
        }
    }

    @Test
    func `Set merge true is no-op when already set`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)
        do {
            let xcodeproj = try XcodeProj(path: projectPath)
            let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
            let phase = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
            phase.files!.first!.settings = ["ATTRIBUTES": .array(["Merge"])]
            try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())
        }

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyLib.framework"),
            "merge": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("already has merge=true"))
        #expect(message.contains("No changes made"))
    }

    @Test
    func `Set merge false is no-op when not set`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyLib.framework"),
            "merge": Value.bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("already has merge=false"))
    }

    @Test
    func `Framework not found in phase`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("NotPresent.framework"),
            "merge": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("No frameworks-phase entry matching 'NotPresent.framework'"))
    }

    @Test
    func `Target without frameworks phase`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("Anything"),
            "merge": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("has no PBXFrameworksBuildPhase"))
    }

    @Test
    func `Set merge true on SPM productRef matched by productName`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        do {
            let xcodeproj = try XcodeProj(path: projectPath)
            let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!

            let pkg = XCRemoteSwiftPackageReference(
                repositoryURL: "https://example.com/MyPackage.git",
                versionRequirement: .upToNextMajorVersion("1.0.0"),
            )
            xcodeproj.pbxproj.add(object: pkg)
            let productRef = XCSwiftPackageProductDependency(
                productName: "MyProduct", package: pkg,
            )
            xcodeproj.pbxproj.add(object: productRef)

            let buildFile = PBXBuildFile(product: productRef)
            xcodeproj.pbxproj.add(object: buildFile)

            let frameworksPhase = PBXFrameworksBuildPhase(files: [buildFile])
            xcodeproj.pbxproj.add(object: frameworksPhase)
            target.buildPhases.append(frameworksPhase)

            try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())
        }

        let tool = SetFrameworkMergeAttributeTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyProduct"),
            "merge": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("merge=true"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        let phase = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }.first!
        let buildFile = phase.files!.first!
        if case let .array(attrs) = buildFile.settings?["ATTRIBUTES"] {
            #expect(attrs.contains("Merge"))
        } else {
            Issue.record("Expected ATTRIBUTES array on SPM productRef build file")
        }
    }

    @Test
    func `list_frameworks_phase surfaces merge=true marker`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let (projectPath, _) = try Self.makeProjectWithFramework(at: tempDir)

        // Toggle merge=true via the tool.
        let setTool = SetFrameworkMergeAttributeTool(
            pathUtility: PathUtility(basePath: tempDir.path),
        )
        _ = try setTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "framework_name": Value.string("MyLib.framework"),
            "merge": Value.bool(true),
        ])

        let listTool = ListFrameworksPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try listTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result"); return
        }
        #expect(message.contains("MyLib.framework"))
        #expect(message.contains("merge=true"))
    }
}
