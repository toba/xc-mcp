import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RepairProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "repair_project")
        #expect(toolDefinition.description?.contains("Repair") == true)
    }

    @Test
    func `Missing project_path throws`() throws {
        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
    }

    @Test
    func `Clean project reports no issues`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("No issues found"))
    }

    @Test
    func `Removes null build file references`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add null build files to sources phase
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let sourcesPhase = try #require(
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase)

        let nullBuildFile1 = PBXBuildFile(file: nil)
        let nullBuildFile2 = PBXBuildFile(file: nil)
        xcodeproj.pbxproj.add(object: nullBuildFile1)
        xcodeproj.pbxproj.add(object: nullBuildFile2)
        sourcesPhase.files = (sourcesPhase.files ?? []) + [nullBuildFile1, nullBuildFile2]
        try xcodeproj.write(path: projectPath)

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("null build file"))
        #expect(content.contains("applied"))

        // Verify the null files were actually removed
        let repaired = try XcodeProj(path: projectPath)
        let repairedTarget = try #require(repaired.pbxproj.nativeTargets.first { $0.name == "App" })
        let repairedSources = try #require(repairedTarget.buildPhases.first {
            $0 is PBXSourcesBuildPhase
        })
        let nullCount = (repairedSources.files ?? [])
            .count(where: { $0.file == nil && $0.product == nil })
        #expect(nullCount == 0)
    }

    @Test
    func `Dry run reports fixes without modifying`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a null build file
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let sourcesPhase = try #require(
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase)
        let nullBuildFile = PBXBuildFile(file: nil)
        xcodeproj.pbxproj.add(object: nullBuildFile)
        sourcesPhase.files = (sourcesPhase.files ?? []) + [nullBuildFile]
        try xcodeproj.write(path: projectPath)

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "dry_run": .bool(true),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Dry Run"))
        #expect(content.contains("would apply"))

        // Verify the file was NOT modified
        let unchanged = try XcodeProj(path: projectPath)
        let unchangedTarget = try #require(unchanged.pbxproj.nativeTargets.first {
            $0.name == "App"
        })
        let unchangedSources = try #require(unchangedTarget.buildPhases.first {
            $0 is PBXSourcesBuildPhase
        })
        let nullCount = (unchangedSources.files ?? [])
            .count(where: { $0.file == nil && $0.product == nil })
        #expect(nullCount == 1)
    }

    @Test
    func `Removes orphaned PBXBuildFile entries`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // First add a real framework to a build phase so PBXBuildFile section exists
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let realRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Real.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: realRef)
        let realBuildFile = PBXBuildFile(file: realRef)
        xcodeproj.pbxproj.add(object: realBuildFile)
        let frameworksPhase = PBXFrameworksBuildPhase(files: [realBuildFile])
        xcodeproj.pbxproj.add(object: frameworksPhase)
        target.buildPhases.append(frameworksPhase)
        try xcodeproj.write(path: projectPath)

        // Inject orphan via text editing
        let pbxprojPath = projectPath + "project.pbxproj"
        var pbxprojText = try String(
            contentsOf: URL(fileURLWithPath: pbxprojPath.string), encoding: .utf8,
        )

        let fileRefUUID = "DEADBEEF00000000DEADBEE1"
        let buildFileUUID = "DEADBEEF00000000DEADBEE2"
        pbxprojText = pbxprojText.replacingOccurrences(
            of: "/* End PBXFileReference section */",
            with: """
                \t\t\(fileRefUUID) /* Orphan.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Orphan.framework; sourceTree = BUILT_PRODUCTS_DIR; };
                /* End PBXFileReference section */
                """,
        )
        pbxprojText = pbxprojText.replacingOccurrences(
            of: "/* End PBXBuildFile section */",
            with: """
                \t\t\(buildFileUUID) /* Orphan.framework */ = {isa = PBXBuildFile; fileRef = \(fileRefUUID) /* Orphan.framework */; };
                /* End PBXBuildFile section */
                """,
        )
        try pbxprojText.write(toFile: pbxprojPath.string, atomically: true, encoding: .utf8)

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("orphaned PBXBuildFile"))
        #expect(content.contains("applied"))
    }

    @Test
    func `Garbage-collects orphaned target dependency and proxy objects`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Inject a PBXTargetDependency + PBXContainerItemProxy that no target's `dependencies`
        // array references — exactly the orphan a buggy dependent-target removal left behind.
        let xcodeproj = try XcodeProj(path: projectPath)
        let app = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let proxy = try PBXContainerItemProxy(
            containerPortal: .project(#require(xcodeproj.pbxproj.rootObject)),
            remoteGlobalID: .object(app),
            proxyType: .nativeTarget,
            remoteInfo: "App",
        )
        xcodeproj.pbxproj.add(object: proxy)
        let dependency = PBXTargetDependency(name: "App", target: app, targetProxy: proxy)
        xcodeproj.pbxproj.add(object: dependency)
        // Deliberately NOT appended to any target's dependencies — this is the orphan.
        try xcodeproj.write(path: projectPath)

        #expect(try XcodeProj(path: projectPath).pbxproj.targetDependencies.count == 1)

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("orphaned PBXTargetDependency"))
        #expect(content.contains("orphaned PBXContainerItemProxy"))
        #expect(content.contains("applied"))

        let repaired = try XcodeProj(path: projectPath)
        #expect(repaired.pbxproj.targetDependencies.isEmpty)
        #expect(repaired.pbxproj.containerItemProxies.isEmpty)
    }

    @Test
    func `Removes self-referencing sub-project entries`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )
        try TestProjectHelper.injectSelfProjectReferences(
            name: "TestProject", count: 4, at: projectPath,
        )

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: ["project_path": .string(projectPath.string)])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("self-referencing sub-project"))
        #expect(content.contains("4"))
        #expect(content.contains("applied"))

        // Verify the entries were actually removed.
        let repaired = try XcodeProj(path: projectPath)
        #expect(SelfProjectReference.detect(in: repaired, projectPath: projectPath.string).isEmpty)
        #expect(repaired.pbxproj.rootObject?.projects.isEmpty == true)
    }

    @Test
    func `Dry run leaves self-references intact`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )
        try TestProjectHelper.injectSelfProjectReferences(
            name: "TestProject", count: 1, at: projectPath,
        )

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "dry_run": .bool(true),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("self-referencing sub-project"))

        // Verify nothing was written.
        let unchanged = try XcodeProj(path: projectPath)
        #expect(
            SelfProjectReference.detect(in: unchanged, projectPath: projectPath.string).count == 1)
    }
}
