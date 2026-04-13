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
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
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
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

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
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase,
        )

        let nullBuildFile1 = PBXBuildFile(file: nil)
        let nullBuildFile2 = PBXBuildFile(file: nil)
        xcodeproj.pbxproj.add(object: nullBuildFile1)
        xcodeproj.pbxproj.add(object: nullBuildFile2)
        sourcesPhase.files = (sourcesPhase.files ?? []) + [nullBuildFile1, nullBuildFile2]
        try xcodeproj.write(path: projectPath)

        let tool = RepairProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("null build file"))
        #expect(content.contains("applied"))

        // Verify the null files were actually removed
        let repaired = try XcodeProj(path: projectPath)
        let repairedTarget = try #require(
            repaired.pbxproj.nativeTargets.first { $0.name == "App" },
        )
        let repairedSources = try #require(
            repairedTarget.buildPhases.first { $0 is PBXSourcesBuildPhase },
        )
        let nullCount = (repairedSources.files ?? []).filter { $0.file == nil && $0.product == nil }
            .count
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
            target.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase,
        )
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
        let unchangedTarget = try #require(
            unchanged.pbxproj.nativeTargets.first { $0.name == "App" },
        )
        let unchangedSources = try #require(
            unchangedTarget.buildPhases.first { $0 is PBXSourcesBuildPhase },
        )
        let nullCount =
            (unchangedSources.files ?? []).filter { $0.file == nil && $0.product == nil }.count
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
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("orphaned PBXBuildFile"))
        #expect(content.contains("applied"))
    }
}
