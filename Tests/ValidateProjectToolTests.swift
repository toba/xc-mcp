import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ValidateProjectToolTests {
    @Test
    func `Tool creation`() {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "validate_project")
        #expect(toolDefinition.description?.contains("Validate") == true)
    }

    @Test
    func `Missing project_path throws`() throws {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }
    }

    @Test
    func `Invalid project path throws`() throws {
        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": .string("/nonexistent/path.xcodeproj")])
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

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
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
    func `Detects embed phase with nil dstSubfolderSpec`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[error]"))
        #expect(content.contains("dstSubfolder=None"))
        #expect(content.contains("1 error"))
    }

    @Test
    func `Detects empty copy-files phase`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[warn]"))
        #expect(content.contains("zero files"))
    }

    @Test
    func `Detects duplicate framework in multiple phases`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[error]"))
        #expect(content.contains("appears in both"))
    }

    @Test
    func `Detects linked but not embedded framework`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[warn]"))
        #expect(content.contains("MathView.framework linked but not embedded"))
    }

    @Test
    func `Reports correctly linked and embedded frameworks`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("1 framework linked and embedded correctly"))
    }

    @Test
    func `Detects dangling file reference in copy-files phase`() throws {
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

        // Create a build file with no file reference (dangling)
        let buildFile = PBXBuildFile(file: nil)
        xcodeproj.pbxproj.add(object: buildFile)

        let phase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .resources,
            name: "Copy Resources",
            files: [buildFile],
        )
        xcodeproj.pbxproj.add(object: phase)
        target.buildPhases.append(phase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("[warn]"))
        #expect(content.contains("dangling reference"))
    }

    @Test
    func `Detects orphaned PBXBuildFile entries`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework to a build phase so PBXBuildFile section exists, then add an orphan
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })

        // Add a real framework to a build phase
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

        // Also add an orphan build file
        let orphanRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Orphan.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: orphanRef)
        let orphanBuildFile = PBXBuildFile(file: orphanRef)
        xcodeproj.pbxproj.add(object: orphanBuildFile)
        try xcodeproj.write(path: projectPath)

        // Inject orphan directly into pbxproj text since XcodeProj may prune on write
        let pbxprojPath = projectPath + "project.pbxproj"
        let pbxprojText = try String(contentsOf: URL(fileURLWithPath: pbxprojPath.string))

        // Verify the orphan survived write — if PBXBuildFile section has 2 entries we're good.
        // If XcodeProj pruned it, inject manually.
        let buildFileCount = pbxprojText.components(separatedBy: "isa = PBXBuildFile").count - 1
        if buildFileCount < 2 {
            // XcodeProj pruned the orphan; inject it manually
            let fileRefUUID = "DEADBEEF00000000DEADBEE1"
            let buildFileUUID = "DEADBEEF00000000DEADBEE2"
            var modified = pbxprojText
            modified = modified.replacingOccurrences(
                of: "/* End PBXFileReference section */",
                with: """
                \t\t\(
                    fileRefUUID
                ) /* Orphan.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Orphan.framework; sourceTree = BUILT_PRODUCTS_DIR; };
                /* End PBXFileReference section */
                """,
            )
            modified = modified.replacingOccurrences(
                of: "/* End PBXBuildFile section */",
                with: """
                \t\t\(buildFileUUID) /* Orphan.framework */ = {isa = PBXBuildFile; fileRef = \(
                    fileRefUUID
                ) /* Orphan.framework */; };
                /* End PBXBuildFile section */
                """,
            )
            try modified.write(toFile: pbxprojPath.string, atomically: true, encoding: .utf8)
        }

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Project-level"))
        #expect(content.contains("orphaned PBXBuildFile"))
    }

    @Test
    func `Detects build phase not referenced by any target`() throws {
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

        // Add a build phase not attached to any target
        let floatingPhase = PBXSourcesBuildPhase()
        xcodeproj.pbxproj.add(object: floatingPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Project-level"))
        #expect(content.contains("not referenced by any target"))
    }

    @Test
    func `Detects inconsistent embedding across app targets`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "App1", target2: "App2", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let app1 = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App1" })

        // Embed a framework only in App1
        let fileRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            explicitFileType: "wrapper.framework",
            path: "Core.framework",
            includeInIndex: false,
        )
        xcodeproj.pbxproj.add(object: fileRef)
        let buildFile = PBXBuildFile(file: fileRef)
        xcodeproj.pbxproj.add(object: buildFile)
        let embedPhase = PBXCopyFilesBuildPhase(
            dstPath: "",
            dstSubfolderSpec: .frameworks,
            name: "Embed Frameworks",
            files: [buildFile],
        )
        xcodeproj.pbxproj.add(object: embedPhase)
        app1.buildPhases.append(embedPhase)
        try xcodeproj.write(path: projectPath)

        let tool = ValidateProjectTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
        ])

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Core.framework embedded in App1 but not all app targets"))
    }

    @Test
    func `Detects missing target dependency`() throws {
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

        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(content.contains("Links Core.framework from Core but has no target dependency"))
    }
}
