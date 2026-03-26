import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for parameterized product type tests
struct ProductTypeTestCase {
    let targetName: String
    let productTypeString: String
    let expectedProductTypeRawValue: String
    let platform: String?
    let deploymentTarget: String?

    var expectedProductType: PBXProductType {
        PBXProductType(rawValue: expectedProductTypeRawValue)!
    }

    init(
        _ targetName: String,
        _ productTypeString: String,
        _ expectedProductType: PBXProductType,
        platform: String? = nil,
        deploymentTarget: String? = nil,
    ) {
        self.targetName = targetName
        self.productTypeString = productTypeString
        expectedProductTypeRawValue = expectedProductType.rawValue
        self.platform = platform
        self.deploymentTarget = deploymentTarget
    }
}

/// Test case for missing parameter validation
struct MissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct AddTargetToolTests {
    @Test
    func `Tool creation`() {
        let tool = AddTargetTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_target")
        #expect(toolDefinition.description == "Create a new target")
    }

    static let missingParamCases: [MissingParamTestCase] = [
        MissingParamTestCase(
            "Missing project_path",
            [
                "target_name": Value.string("NewTarget"),
                "product_type": Value.string("app"),
                "bundle_identifier": Value.string("com.test.newtarget"),
            ],
        ),
        MissingParamTestCase(
            "Missing target_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "product_type": Value.string("app"),
                "bundle_identifier": Value.string("com.test.newtarget"),
            ],
        ),
        MissingParamTestCase(
            "Missing product_type",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("NewTarget"),
                "bundle_identifier": Value.string("com.test.newtarget"),
            ],
        ),
        MissingParamTestCase(
            "Missing bundle_identifier",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("NewTarget"),
                "product_type": Value.string("app"),
            ],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Add target with missing parameters`(_ testCase: MissingParamTestCase) throws {
        let tool = AddTargetTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    static let productTypeCases: [ProductTypeTestCase] = [
        ProductTypeTestCase("NewApp", "app", .application),
        ProductTypeTestCase(
            "MyFramework", "framework", .framework, platform: "iOS", deploymentTarget: "15.0",
        ),
        ProductTypeTestCase("MyAppTests", "unitTestBundle", .unitTestBundle),
        ProductTypeTestCase("StaticFramework", "staticFramework", .staticFramework),
        ProductTypeTestCase("MyXCFramework", "xcFramework", .xcFramework),
        ProductTypeTestCase("MyExtension", "appExtension", .appExtension),
        ProductTypeTestCase("MyTool", "commandLineTool", .commandLineTool, platform: "macOS"),
        ProductTypeTestCase("MyWatchApp", "watchApp", .watchApp, platform: "watchOS"),
        ProductTypeTestCase("MyMessagesExtension", "messagesExtension", .messagesExtension),
        ProductTypeTestCase("MyXPCService", "xpcService", .xpcService, platform: "macOS"),
    ]

    @Test(arguments: productTypeCases)
    func `Add target with product type`(_ testCase: ProductTypeTestCase) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        var args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string(testCase.targetName),
            "product_type": Value.string(testCase.productTypeString),
            "bundle_identifier": Value.string("com.test.\(testCase.targetName.lowercased())"),
        ]

        if let platform = testCase.platform {
            args["platform"] = Value.string(platform)
        }
        if let deploymentTarget = testCase.deploymentTarget {
            args["deployment_target"] = Value.string(deploymentTarget)
        }

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully created target '\(testCase.targetName)'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == testCase.targetName }
        #expect(target != nil)
        #expect(target?.productType == testCase.expectedProductType)

        // Verify product reference
        let productRef = target?.product
        #expect(productRef != nil, "Target should have a productReference")
        #expect(productRef?.sourceTree == .buildProductsDir)
        #expect(productRef?.includeInIndex == false)
        #expect(
            productRef?.explicitFileType == testCase.expectedProductType.explicitFileType,
        )

        // Verify product is in Products group
        let productsGroup = xcodeproj.pbxproj.rootObject?.productsGroup
        #expect(productsGroup != nil, "Project should have a Products group")
        let productInGroup = productsGroup?.children.contains { $0 === productRef } ?? false
        #expect(productInGroup, "Product reference should be in the Products group")

        // Verify minimal settings are present
        let anyConfig = target?.buildConfigurationList?.buildConfigurations.first
        #expect(anyConfig?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] != nil)
        #expect(anyConfig?.buildSettings["PRODUCT_NAME"] != nil)

        if let deploymentTarget = testCase.deploymentTarget, testCase.platform == "iOS" {
            let buildConfig = target?.buildConfigurationList?.buildConfigurations.first {
                $0.name == "Debug"
            }
            #expect(
                buildConfig?.buildSettings["IPHONEOS_DEPLOYMENT_TARGET"]?.stringValue
                    == deploymentTarget,
            )
        }
    }

    @Test
    func `Add application target verifies build phases`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NewApp"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.newapp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("product type 'app'"))
        #expect(message.contains("bundle identifier 'com.test.newapp'"))

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "NewApp" }

        // Verify build phases were created
        #expect(target?.buildPhases.contains { $0 is PBXSourcesBuildPhase } == true)
        #expect(target?.buildPhases.contains { $0 is PBXResourcesBuildPhase } == true)
        #expect(target?.buildPhases.contains { $0 is PBXFrameworksBuildPhase } == true)

        // Verify build configurations
        let buildConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        #expect(
            buildConfig?.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"]?
                .stringValue == "com.test.newapp",
        )
        #expect(
            buildConfig?.buildSettings["GENERATE_INFOPLIST_FILE"]?.stringValue == "YES",
        )
        // Verify inherited settings are NOT present
        #expect(buildConfig?.buildSettings["BUNDLE_IDENTIFIER"] == nil)
        #expect(buildConfig?.buildSettings["ALWAYS_SEARCH_USER_PATHS"] == nil)
        #expect(buildConfig?.buildSettings["SWIFT_VERSION"] == nil)
        #expect(buildConfig?.buildSettings["INFOPLIST_FILE"] == nil)
        #expect(buildConfig?.buildSettings["ONLY_ACTIVE_ARCH"] == nil)
    }

    @Test
    func `Add duplicate target`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TestApp"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.testapp"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test
    func `Add macOS target does not set TARGETED_DEVICE_FAMILY`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("MacApp"),
            "product_type": Value.string("app"),
            "bundle_identifier": Value.string("com.test.macapp"),
            "platform": Value.string("macOS"),
        ]

        _ = try tool.execute(arguments: args)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "MacApp" }
        let buildConfig = target?.buildConfigurationList?.buildConfigurations.first {
            $0.name == "Debug"
        }
        #expect(buildConfig?.buildSettings["TARGETED_DEVICE_FAMILY"] == nil)
        #expect(buildConfig?.buildSettings["ALWAYS_SEARCH_USER_PATHS"] == nil)
    }

    @Test
    func `Add target matches all project build configurations`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a project with 3 configs: Debug, Release, Beta
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        let pbxproj = PBXProj()
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        let betaConfig = XCBuildConfiguration(name: "Beta", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)
        pbxproj.add(object: betaConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig, betaConfig],
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

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NewFramework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.newframework"),
        ]

        _ = try tool.execute(arguments: args)

        let reloaded = try XcodeProj(path: projectPath)
        let target = reloaded.pbxproj.nativeTargets.first { $0.name == "NewFramework" }
        let configNames = target?.buildConfigurationList?.buildConfigurations.map(\.name) ?? []
        #expect(configNames.count == 3)
        #expect(configNames.contains("Debug"))
        #expect(configNames.contains("Release"))
        #expect(configNames.contains("Beta"))
    }

    @Test
    func `Add target with parent_group`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a "Components" group first
        let xcodeproj = try XcodeProj(path: projectPath)
        let componentsGroup = PBXGroup(
            sourceTree: .group, name: "Components", path: "Components",
        )
        xcodeproj.pbxproj.add(object: componentsGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(componentsGroup)
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("TableView"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.tableview"),
            "parent_group": Value.string("Components"),
        ]

        _ = try tool.execute(arguments: args)

        let reloaded = try XcodeProj(path: projectPath)
        let compGroup = reloaded.pbxproj.groups.first { $0.name == "Components" }
        let childNames = compGroup?.children.compactMap { ($0 as? PBXGroup)?.name } ?? []
        #expect(childNames.contains("TableView"))

        // Verify target group is NOT in mainGroup directly
        let mainGroup = try reloaded.pbxproj.rootProject()?.mainGroup
        let rootChildNames = mainGroup?.children.compactMap { ($0 as? PBXGroup)?.name } ?? []
        #expect(!rootChildNames.contains("TableView"))
    }

    @Test
    func `Add target with invalid parent_group`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NewTarget"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.newtarget"),
            "parent_group": Value.string("NonExistent/Group"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test
    func `Add target with invalid product type`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let tool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NewTarget"),
            "product_type": Value.string("invalid_type"),
            "bundle_identifier": Value.string("com.test.newtarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
