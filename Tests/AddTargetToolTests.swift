import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for parameterized product type tests
struct ProductTypeTestCase: Sendable {
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
struct MissingParamTestCase: Sendable {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

@Suite("AddTargetTool Tests")
struct AddTargetToolTests {
    @Test("Tool creation")
    func toolCreation() {
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

    @Test("Add target with missing parameters", arguments: missingParamCases)
    func addTargetWithMissingParameters(_ testCase: MissingParamTestCase) throws {
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

    @Test("Add target with product type", arguments: productTypeCases)
    func addTargetWithProductType(_ testCase: ProductTypeTestCase) throws {
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

        guard case let .text(message) = result.content.first else {
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

    @Test("Add application target verifies build phases")
    func addApplicationTargetVerifiesBuildPhases() throws {
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

        guard case let .text(message) = result.content.first else {
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
        #expect(buildConfig?.buildSettings["BUNDLE_IDENTIFIER"]?.stringValue == "com.test.newapp")
    }

    @Test("Add duplicate target")
    func addDuplicateTarget() throws {
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

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already exists"))
    }

    @Test("Add macOS target does not set TARGETED_DEVICE_FAMILY")
    func addMacOSTargetNoDeviceFamily() throws {
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
        #expect(buildConfig?.buildSettings["ALWAYS_SEARCH_USER_PATHS"] == .string("NO"))
    }

    @Test("Add target with invalid product type")
    func addTargetWithInvalidProductType() throws {
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
