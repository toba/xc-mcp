import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveTargetToolTests {
    @Test
    func `Tool creation`() {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "remove_target")
        #expect(toolDefinition.description == "Remove an existing target")
    }

    @Test
    func `Remove target with missing project path`() throws {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["target_name": Value.string("TestTarget")])
        }
    }

    @Test
    func `Remove target with missing target name`() throws {
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(
                arguments: ["project_path": Value.string("/path/to/project.xcodeproj")],
            )
        }
    }

    @Test
    func `Remove existing target`() throws {
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
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        // Verify target exists
        var xcodeproj = try XcodeProj(path: projectPath)
        let targetExists = xcodeproj.pbxproj.nativeTargets.contains { $0.name == "TestApp" }
        #expect(targetExists == true)

        // Remove the target
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestApp"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'TestApp'"))

        // Verify target was removed
        xcodeproj = try XcodeProj(path: projectPath)
        let targetStillExists = xcodeproj.pbxproj.nativeTargets.contains { $0.name == "TestApp" }
        #expect(targetStillExists == false)
    }

    @Test
    func `Remove non-existent target`() throws {
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

        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }

    @Test
    func `Remove target with dependencies`() throws {
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
            name: "TestProject", targetName: "MainApp", at: projectPath,
        )

        // Add another target
        let addTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTool.execute(arguments: addArgs)

        // Remove the framework target
        let removeTool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let removeArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
        ]

        let result = try removeTool.execute(arguments: removeArgs)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'Framework'"))

        // Verify only the framework target was removed
        let xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.count == 1)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.name == "MainApp")
    }

    @Test
    func `Remove target cleans up dependency and proxy objects`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a project with two targets where AppTarget depends on LibTarget
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "LibTarget", at: projectPath,
        )

        // Wire up a real dependency: AppTarget depends on LibTarget
        var xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = try #require(
            xcodeproj.pbxproj.nativeTargets
                .first { $0.name == "AppTarget" },
        )
        let libTarget = try #require(
            xcodeproj.pbxproj.nativeTargets
                .first { $0.name == "LibTarget" },
        )

        let proxy = try PBXContainerItemProxy(
            containerPortal: .project(#require(xcodeproj.pbxproj.rootObject)),
            remoteGlobalID: .object(libTarget),
            proxyType: .nativeTarget,
            remoteInfo: "LibTarget",
        )
        xcodeproj.pbxproj.add(object: proxy)

        let dependency = PBXTargetDependency(
            name: "LibTarget",
            target: libTarget,
            targetProxy: proxy,
        )
        xcodeproj.pbxproj.add(object: dependency)
        appTarget.dependencies.append(dependency)

        try xcodeproj.write(path: projectPath)

        // Verify the dependency objects exist
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.targetDependencies.count == 1)
        #expect(xcodeproj.pbxproj.containerItemProxies.count == 1)

        // Remove LibTarget. AppTarget depends on it, so the removal must be explicit (cascade).
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("LibTarget"),
            "cascade": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'LibTarget'"))

        // Verify orphaned objects were cleaned up
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.count == 1)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.name == "AppTarget")
        #expect(xcodeproj.pbxproj.targetDependencies.isEmpty)
        #expect(xcodeproj.pbxproj.containerItemProxies.isEmpty)
        #expect(xcodeproj.pbxproj.nativeTargets.first?.dependencies.isEmpty == true)
    }

    @Test
    func `Remove dependent target cleans up its own outgoing dependency and proxy`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // AppTarget depends on LibTarget. We remove the DEPENDENT (AppTarget). Its outgoing
        // dependency edge + proxy must be deleted, not left orphaned pointing at LibTarget —
        // otherwise the orphan later blocks LibTarget's own removal. (qlc-4j9)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "LibTarget", at: projectPath,
        )

        var xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" })
        let libTarget = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "LibTarget" })
        let proxy = try PBXContainerItemProxy(
            containerPortal: .project(#require(xcodeproj.pbxproj.rootObject)),
            remoteGlobalID: .object(libTarget),
            proxyType: .nativeTarget,
            remoteInfo: "LibTarget",
        )
        xcodeproj.pbxproj.add(object: proxy)
        let dependency = PBXTargetDependency(name: "LibTarget", target: libTarget, targetProxy: proxy)
        xcodeproj.pbxproj.add(object: dependency)
        appTarget.dependencies.append(dependency)
        try xcodeproj.write(path: projectPath)

        // Remove the dependent. Nothing depends on AppTarget, so no cascade is needed.
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTarget"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'AppTarget'"))

        // No orphaned outgoing edge may survive, and the now-loadable project must still let
        // LibTarget be removed.
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.targetDependencies.isEmpty)
        #expect(xcodeproj.pbxproj.containerItemProxies.isEmpty)
        let data = try Data(contentsOf: URL(fileURLWithPath: (projectPath + "project.pbxproj").string))
        #expect(PBXProjReferenceAudit.danglingReferences(in: data).isEmpty)

        // The depended-on target can now be removed cleanly (the regression this prevents).
        let second = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("LibTarget"),
        ])
        guard case let .text(secondMessage, _, _) = second.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(secondMessage.contains("Successfully removed target 'LibTarget'"))
    }

    @Test
    func `Remove target cascades to test plans referencing it`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "AppTargetTests", at: projectPath,
        )

        // A test plan that references the target we are about to remove.
        let planPath = tempDir.appendingPathComponent("Tests.xctestplan").path
        let plan: [String: Any] = [
            "version": 1,
            "testTargets": [
                ["target": [
                    "containerPath": "container:TestProject.xcodeproj",
                    "identifier": "ABC123",
                    "name": "AppTargetTests",
                ]],
            ],
        ]
        try TestPlanFile.write(plan, to: planPath)

        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTargetTests"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'AppTargetTests'"))
        #expect(message.contains("Tests.xctestplan"))

        // The dangling reference must be gone from the test plan.
        let updated = try TestPlanFile.read(from: planPath)
        #expect(!TestPlanFile.targetNames(from: updated).contains("AppTargetTests"))
    }

    @Test
    func `Remove target cascades to schemes referencing it`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "AppTargetTests", at: projectPath,
        )

        // A shared scheme whose TestAction references the target we are about to remove.
        let schemeDir = projectPath.string + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(
            atPath: schemeDir, withIntermediateDirectories: true,
        )
        let schemePath = "\(schemeDir)/AppTarget.xcscheme"
        let schemeXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion="1600" version="1.7">
           <TestAction buildConfiguration="Debug">
              <Testables>
                 <TestableReference skipped="NO">
                    <BuildableReference
                       BuildableIdentifier="primary"
                       BlueprintIdentifier="ABC123"
                       BuildableName="AppTargetTests.xctest"
                       BlueprintName="AppTargetTests"
                       ReferencedContainer="container:TestProject.xcodeproj">
                    </BuildableReference>
                 </TestableReference>
              </Testables>
           </TestAction>
        </Scheme>
        """
        try schemeXML.write(toFile: schemePath, atomically: true, encoding: .utf8)

        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTargetTests"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'AppTargetTests'"))
        #expect(message.contains("AppTarget.xcscheme"))

        // No dangling reference may remain in the scheme.
        #expect(!SchemeTargetEditor.references(
            target: "AppTargetTests",
            projectFilename: "TestProject.xcodeproj",
            schemeAt: schemePath,
        ))
    }

    @Test
    func `Remove target with product embedded in another target does not crash`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "HostApp", target2: "Helper", at: projectPath,
        )

        // Give Helper a product and embed it in HostApp via a copy-files build phase. A leftover
        // build file pointing at the deleted product is what traps XcodeProj's serializer.
        var xcodeproj = try XcodeProj(path: projectPath)
        let host = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "HostApp" })
        let helper = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "Helper" })

        let product = PBXFileReference(sourceTree: .buildProductsDir, name: "Helper.framework")
        xcodeproj.pbxproj.add(object: product)
        helper.product = product
        xcodeproj.pbxproj.rootObject?.productsGroup?.children.append(product)

        let buildFile = PBXBuildFile(file: product)
        xcodeproj.pbxproj.add(object: buildFile)
        let embedPhase = PBXCopyFilesBuildPhase(
            dstSubfolderSpec: .frameworks, name: "Embed Frameworks", files: [buildFile],
        )
        xcodeproj.pbxproj.add(object: embedPhase)
        host.buildPhases.append(embedPhase)
        try xcodeproj.write(path: projectPath)

        // Removing Helper must succeed and not leave a dangling build file. HostApp embeds Helper's
        // product, so the removal must be explicit (cascade).
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Helper"),
            "cascade": Value.bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'Helper'"))

        xcodeproj = try XcodeProj(path: projectPath)
        #expect(!xcodeproj.pbxproj.nativeTargets.contains { $0.name == "Helper" })
        // The embedded build file referencing the now-deleted product must be gone.
        #expect(xcodeproj.pbxproj.buildFiles.allSatisfy { $0.file !== product })
    }

    @Test
    func `Remove target referenced by another target refuses without cascade`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "LibTarget", at: projectPath,
        )

        // Wire AppTarget -> depends on LibTarget.
        var xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTarget" })
        let libTarget = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "LibTarget" })
        let proxy = try PBXContainerItemProxy(
            containerPortal: .project(#require(xcodeproj.pbxproj.rootObject)),
            remoteGlobalID: .object(libTarget),
            proxyType: .nativeTarget,
            remoteInfo: "LibTarget",
        )
        xcodeproj.pbxproj.add(object: proxy)
        let dependency = PBXTargetDependency(name: "LibTarget", target: libTarget, targetProxy: proxy)
        xcodeproj.pbxproj.add(object: dependency)
        appTarget.dependencies.append(dependency)
        try xcodeproj.write(path: projectPath)

        // Without cascade, the removal must refuse and the target must remain.
        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("LibTarget"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Refusing to remove target 'LibTarget'"))
        #expect(message.contains("AppTarget"))
        #expect(message.contains("cascade=true"))

        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "LibTarget" })
    }

    @Test
    func `Remove target cleans up synchronized exception set and target attributes`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "AppTarget", target2: "AppTargetTests", at: projectPath,
        )

        // Give AppTargetTests a synchronized root group with a build-file exception set, and a
        // TargetAttributes entry — both keyed/pointed at the target we will remove. These are the
        // dangling references the thesis corruption left behind.
        var xcodeproj = try XcodeProj(path: projectPath)
        let project = try #require(xcodeproj.pbxproj.rootObject)
        let tests = try #require(
            xcodeproj.pbxproj.nativeTargets.first { $0.name == "AppTargetTests" })

        let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
            target: tests,
            membershipExceptions: ["TestData"],
            publicHeaders: nil,
            privateHeaders: nil,
            additionalCompilerFlagsByRelativePath: nil,
            attributesByRelativePath: nil,
        )
        xcodeproj.pbxproj.add(object: exceptionSet)
        let syncGroup = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "AppTargetTests", exceptions: [exceptionSet],
        )
        xcodeproj.pbxproj.add(object: syncGroup)
        project.mainGroup.children.append(syncGroup)
        project.setTargetAttributes(["CreatedOnToolsVersion": .string("16.3")], target: tests)
        try xcodeproj.write(path: projectPath)

        let tool = RemoveTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("AppTargetTests"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully removed target 'AppTargetTests'"))

        // The exception set and TargetAttributes entry must be gone, leaving no dangling reference.
        xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.fileSystemSynchronizedBuildFileExceptionSets.isEmpty)
        #expect(try #require(xcodeproj.pbxproj.rootObject).targetAttributes.isEmpty)

        let data = try Data(contentsOf: URL(fileURLWithPath: (projectPath + "project.pbxproj").string))
        #expect(PBXProjReferenceAudit.danglingReferences(in: data).isEmpty)
    }
}
