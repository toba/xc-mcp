import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListFrameworksPhaseToolTests {
    @Test
    func `Tool metadata`() {
        let tool = ListFrameworksPhaseTool(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "list_frameworks_phase")
    }

    @Test
    func `Missing parameters throw`() throws {
        let tool = ListFrameworksPhaseTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/x.xcodeproj")])
        }
    }

    @Test
    func `Reports missing target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = ListFrameworksPhaseTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("Ghost"),
        ])
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(content.contains("not found"))
    }

    @Test
    func `Classifies a plain fileRef framework`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let pathUtility = PathUtility(basePath: tempDir.path)
        _ = try AddFrameworkTool(pathUtility: pathUtility).execute(arguments: [
            "project_path": .string(projectPath.string),
            "framework_name": .string("UIKit"),
            "target_name": .string("App"),
        ])

        let tool = ListFrameworksPhaseTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(content.contains("UIKit"))
        #expect(content.contains("kind=fileRef"))
    }

    @Test
    func `Classifies a PBXReferenceProxy cross-project entry and flags link-only path`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let pathUtility = PathUtility(basePath: tempDir.path)
        _ = try AddTargetTool(pathUtility: pathUtility).execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("Core"),
            "product_type": .string("framework"),
            "bundle_identifier": .string("com.test.core"),
        ])

        // Hand-build a PBXReferenceProxy entry in App's frameworks phase that points at Core via
        // a PBXContainerItemProxy — the same shape as a cross-project framework reference. Don't
        // create a PBXTargetDependency edge: that's the link-only-without-ordering case.
        let xcodeproj = try XcodeProj(path: projectPath)
        let app = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        let core = xcodeproj.pbxproj.nativeTargets.first { $0.name == "Core" }!

        let proxy = PBXContainerItemProxy(
            containerPortal: .project(xcodeproj.pbxproj.rootObject!),
            remoteGlobalID: .object(core),
            proxyType: .reference,
            remoteInfo: "Core",
        )
        xcodeproj.pbxproj.add(object: proxy)
        let refProxy = PBXReferenceProxy(
            fileType: "wrapper.framework",
            path: "Core.framework",
            remote: proxy,
            sourceTree: .buildProductsDir,
        )
        xcodeproj.pbxproj.add(object: refProxy)
        let buildFile = PBXBuildFile(file: refProxy)
        xcodeproj.pbxproj.add(object: buildFile)
        let phase: PBXFrameworksBuildPhase
        if let existing = app.buildPhases.first(where: { $0 is PBXFrameworksBuildPhase })
            as? PBXFrameworksBuildPhase
        {
            phase = existing
        } else {
            phase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: phase)
            app.buildPhases.append(phase)
        }
        phase.files = (phase.files ?? []) + [buildFile]
        try xcodeproj.write(path: projectPath)

        let tool = ListFrameworksPhaseTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ])
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(content.contains("Core.framework"))
        #expect(content.contains("kind=crossProject"))
        #expect(content.contains("remoteInfo=Core"))
        #expect(content.contains("no PBXTargetDependency edge"))

        // validate_project should also catch the same asymmetry as a warning.
        let validate = ValidateProjectTool(pathUtility: pathUtility)
        let valResult = try validate.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])
        guard case let .text(valText, _, _) = valResult.content.first else {
            Issue.record("Expected text")
            return
        }
        #expect(valText.contains("via PBXReferenceProxy"))
        #expect(valText.contains("[warn]"))
    }
}
