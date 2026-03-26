import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ScaffoldModuleToolTests {
    @Test
    func `Tool creation`() {
        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "scaffold_module")
        #expect(toolDefinition.description?.contains("framework module") == true)
    }

    @Test
    func `Missing required parameters`() {
        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/tmp/Test.xcodeproj"),
                "name": Value.string("MyModule"),
                // missing bundle_identifier
            ])
        }
    }

    @Test
    func `Basic scaffold creates framework and test targets`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("NetworkKit"),
            "bundle_identifier": Value.string("com.test.networkkit"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Created framework target 'NetworkKit'"))
        #expect(message.contains("Created test target 'NetworkKitTests'"))

        // Verify targets exist
        let xcodeproj = try XcodeProj(path: projectPath)
        let fwTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NetworkKit" }
        let testTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NetworkKitTests" }
        #expect(fwTarget != nil)
        #expect(testTarget != nil)
        #expect(fwTarget?.productType == .framework)
        #expect(testTarget?.productType == .unitTestBundle)

        // Verify DEFINES_MODULE on framework
        let fwConfig = fwTarget?.buildConfigurationList?.buildConfigurations.first
        #expect(fwConfig?.buildSettings["DEFINES_MODULE"]?.stringValue == "YES")

        // Verify test target depends on framework
        let dep = testTarget?.dependencies.first
        #expect(dep?.target === fwTarget)

        // Verify framework product is linked in test target
        let testFrameworksPhase = testTarget?.buildPhases.first {
            $0 is PBXFrameworksBuildPhase
        } as? PBXFrameworksBuildPhase
        let linkedProduct = testFrameworksPhase?.files?.first?.file
        #expect(linkedProduct === fwTarget?.product)

        // Verify product references in Products group
        let productsGroup = xcodeproj.pbxproj.rootObject?.productsGroup
        #expect(productsGroup?.children.contains { $0 === fwTarget?.product } == true)
        #expect(productsGroup?.children.contains { $0 === testTarget?.product } == true)

        // Verify directories were created
        let projectDir = URL(fileURLWithPath: projectPath.string).deletingLastPathComponent().path
        #expect(
            FileManager.default.fileExists(
                atPath: (projectDir as NSString).appendingPathComponent("NetworkKit"),
            ),
        )
        #expect(
            FileManager.default.fileExists(
                atPath: (projectDir as NSString).appendingPathComponent("NetworkKitTests"),
            ),
        )
    }

    @Test
    func `Scaffold without tests`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("CoreKit"),
            "bundle_identifier": Value.string("com.test.corekit"),
            "with_tests": Value.bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Created framework target 'CoreKit'"))
        #expect(!message.contains("Created test target"))

        let xcodeproj = try XcodeProj(path: projectPath)
        #expect(xcodeproj.pbxproj.nativeTargets.contains { $0.name == "CoreKit" })
        #expect(!xcodeproj.pbxproj.nativeTargets.contains { $0.name == "CoreKitTests" })
    }

    @Test
    func `Scaffold with parent group`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Add a "Modules" group
        let xcodeproj = try XcodeProj(path: projectPath)
        let modulesGroup = PBXGroup(sourceTree: .group, name: "Modules", path: "Modules")
        xcodeproj.pbxproj.add(object: modulesGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(modulesGroup)
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("UIKit2"),
            "bundle_identifier": Value.string("com.test.uikit2"),
            "parent_group": Value.string("Modules"),
            "with_tests": Value.bool(false),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let modGroup = reloaded.pbxproj.groups.first { $0.name == "Modules" }
        let childNames = modGroup?.children.compactMap { ($0 as? PBXGroup)?.name } ?? []
        #expect(childNames.contains("UIKit2"))

        // Not in main group directly
        let mainGroup = try reloaded.pbxproj.rootProject()?.mainGroup
        let rootChildNames = mainGroup?.children.compactMap { ($0 as? PBXGroup)?.name } ?? []
        #expect(!rootChildNames.contains("UIKit2"))
    }

    @Test
    func `Scaffold with link_to and embed_in`() throws {
        let (tempDir, projectPath) = try createTempProjectWithTarget(targetName: "MainApp")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("FeatureKit"),
            "bundle_identifier": Value.string("com.test.featurekit"),
            "link_to": Value.array([Value.string("MainApp")]),
            "embed_in": Value.array([Value.string("MainApp")]),
            "with_tests": Value.bool(false),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let mainApp = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "MainApp" })
        let featureKit = try #require(xcodeproj.pbxproj.nativeTargets
            .first { $0.name == "FeatureKit" })

        // Verify dependency
        #expect(mainApp.dependencies.contains { $0.target === featureKit })

        // Verify framework linked
        let fwPhase = mainApp.buildPhases.first {
            $0 is PBXFrameworksBuildPhase
        } as? PBXFrameworksBuildPhase
        let linkedFiles = fwPhase?.files?.compactMap(\.file) ?? []
        #expect(linkedFiles.contains { $0 === featureKit.product })

        // Verify embed phase exists with CodeSignOnCopy
        let embedPhase = mainApp.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }
            .first { $0.dstSubfolderSpec == .frameworks }
        #expect(embedPhase != nil)
        let embedFile = embedPhase?.files?.first { $0.file === featureKit.product }
        #expect(embedFile != nil)
        let attrs = embedFile?.settings?["ATTRIBUTES"]?.arrayValue ?? []
        #expect(attrs.contains("CodeSignOnCopy"))
    }

    @Test
    func `Scaffold matches all project build configurations`() throws {
        let (tempDir, projectPath) = try createTempProjectWithConfigs(
            ["Debug", "Release", "Staging"],
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("AnalyticsKit"),
            "bundle_identifier": Value.string("com.test.analyticskit"),
            "with_tests": Value.bool(false),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "AnalyticsKit" }
        let configNames =
            target?.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
        #expect(configNames.count == 3)
        #expect(Set(configNames) == Set(["Debug", "Release", "Staging"]))
    }

    @Test
    func `Scaffold with deployment target`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("MyLib"),
            "bundle_identifier": Value.string("com.test.mylib"),
            "platform": Value.string("macOS"),
            "deployment_target": Value.string("14.0"),
            "with_tests": Value.bool(false),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "MyLib" }
        let config = target?.buildConfigurationList?.buildConfigurations.first
        #expect(config?.buildSettings["MACOSX_DEPLOYMENT_TARGET"]?.stringValue == "14.0")
    }

    @Test
    func `Duplicate target name fails`() throws {
        let (tempDir, projectPath) = try createTempProjectWithTarget(targetName: "ExistingKit")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "name": Value.string("ExistingKit"),
                "bundle_identifier": Value.string("com.test.existingkit"),
            ])
        }
    }

    @Test
    func `Invalid link_to target fails`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "name": Value.string("SomeKit"),
                "bundle_identifier": Value.string("com.test.somekit"),
                "link_to": Value.array([Value.string("NonExistent")]),
            ])
        }
    }

    @Test
    func `Scaffold with synchronized folders`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("DataKit"),
            "bundle_identifier": Value.string("com.test.datakit"),
        ])

        let xcodeproj = try XcodeProj(path: projectPath)
        let fwTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "DataKit" }
        let testTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "DataKitTests" }

        // Verify sync groups are wired to targets
        #expect(fwTarget?.fileSystemSynchronizedGroups?.isEmpty == false)
        #expect(testTarget?.fileSystemSynchronizedGroups?.isEmpty == false)
    }

    @Test
    func `Scaffold with test plan`() throws {
        let (tempDir, projectPath) = try createTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test plan file
        let projectDir = URL(fileURLWithPath: projectPath.string)
            .deletingLastPathComponent().path
        let testPlanPath = (projectDir as NSString).appendingPathComponent("AllTests.xctestplan")
        let initialPlan: [String: Any] = [
            "configurations": [["id": "1", "name": "Default", "options": [:]] as [String: Any]],
            "defaultOptions": [:] as [String: Any],
            "testTargets": [] as [[String: Any]],
            "version": 1,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: initialPlan, options: [.prettyPrinted, .sortedKeys],
        )
        try data.write(to: URL(fileURLWithPath: testPlanPath))

        let tool = ScaffoldModuleTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "name": Value.string("AuthKit"),
            "bundle_identifier": Value.string("com.test.authkit"),
            "test_plan": Value.string(testPlanPath),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Added 'AuthKitTests' to test plan"))

        // Verify test plan was updated
        let json = try TestPlanFile.read(from: testPlanPath)
        let names = TestPlanFile.targetNames(from: json)
        #expect(names.contains("AuthKitTests"))
    }

    // MARK: - Helpers

    private func createTempProject() throws -> (URL, Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        return (tempDir, projectPath)
    }

    private func createTempProjectWithTarget(targetName: String) throws -> (URL, Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: targetName, at: projectPath,
        )
        return (tempDir, projectPath)
    }

    private func createTempProjectWithConfigs(_ configs: [String]) throws -> (URL, Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"

        let pbxproj = PBXProj()
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        var buildConfigs: [XCBuildConfiguration] = []
        for name in configs {
            let config = XCBuildConfiguration(name: name, buildSettings: [:])
            pbxproj.add(object: config)
            buildConfigs.append(config)
        }

        let configList = XCConfigurationList(
            buildConfigurations: buildConfigs,
            defaultConfigurationName: "Release",
        )
        pbxproj.add(object: configList)

        let project = PBXProject(
            name: "TestProject",
            buildConfigurationList: configList,
            compatibilityVersion: "Xcode 14.0",
            preferredProjectObjectVersion: 56,
            minimizedProjectReferenceProxies: 0,
            mainGroup: mainGroup,
            developmentRegion: "en",
            knownRegions: ["en", "Base"],
            productsGroup: productsGroup,
        )
        pbxproj.add(object: project)
        pbxproj.rootObject = project

        let workspace = XCWorkspace(data: XCWorkspaceData(children: []))
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: projectPath)

        return (tempDir, projectPath)
    }
}
