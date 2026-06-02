import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for missing parameter validation
struct AddDependencyMissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct AddDependencyToolTests {
    @Test
    func `Tool creation`() {
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_dependency")
        #expect(toolDefinition.description == "Add dependency between targets")
    }

    static let missingParamCases: [AddDependencyMissingParamTestCase] = [
        AddDependencyMissingParamTestCase(
            "Missing project_path",
            ["target_name": Value.string("App"), "dependency_name": Value.string("Framework")],
        ),
        AddDependencyMissingParamTestCase(
            "Missing target_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "dependency_name": Value.string("Framework"),
            ],
        ),
        AddDependencyMissingParamTestCase(
            "Missing dependency_name",
            [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
            ],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Add dependency with missing parameter`(
        _ testCase: AddDependencyMissingParamTestCase,
    ) throws {
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) { try tool.execute(arguments: testCase.arguments) }
    }

    @Test
    func `Add dependency between targets`() throws {
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
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addFrameworkArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTargetTool.execute(arguments: addFrameworkArgs)

        // Add dependency
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains success message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added dependency 'Framework' to target 'App'"))

        // Verify dependency was added
        let xcodeproj = try XcodeProj(path: projectPath)
        let appTarget = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }
        #expect(appTarget != nil)

        let hasDependency = appTarget?.dependencies.contains { dependency in
            dependency.name == "Framework"
        } ?? false
        #expect(hasDependency == true)
    }

    @Test
    func `Add duplicate dependency`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with targets
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Add a framework target
        let addTargetTool = AddTargetTool(pathUtility: PathUtility(basePath: tempDir.path))
        let addFrameworkArgs: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("Framework"),
            "product_type": Value.string("framework"),
            "bundle_identifier": Value.string("com.test.framework"),
        ]
        _ = try addTargetTool.execute(arguments: addFrameworkArgs)

        // Add dependency
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Framework"),
        ]

        _ = try tool.execute(arguments: args)

        // Try to add the same dependency again
        let result = try tool.execute(arguments: args)

        // Check the result contains already exists message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("already depends on"))
    }

    @Test
    func `Add dependency with non-existent target`() throws {
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

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("NonExistentTarget"),
            "dependency_name": Value.string("Framework"),
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
    func `Add cross-project dependency via projectReferences`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Consumer project
        let consumerPath = Path(tempDir.path) + "Consumer.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Consumer", targetName: "App", at: consumerPath,
        )

        // Sub-project containing the dependency target
        let subDir = tempDir.appendingPathComponent("SubProject")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let subPath = Path(subDir.path) + "Sub.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Sub", targetName: "SubFramework", at: subPath,
        )

        // Discover sub-project target UUID for later assertion.
        let subProj = try XcodeProj(path: subPath)
        let subTargetUUID = try #require(
            subProj.pbxproj.nativeTargets.first { $0.name == "SubFramework" }
        ).uuid

        // Wire a projectReferences entry into the consumer project.
        let consumer = try XcodeProj(path: consumerPath)
        let rootObject = try #require(consumer.pbxproj.rootObject)

        let subRef = PBXFileReference(
            sourceTree: .group,
            name: nil,
            lastKnownFileType: "wrapper.pb-project",
            path: "SubProject/Sub.xcodeproj",
        )
        consumer.pbxproj.add(object: subRef)
        rootObject.mainGroup.children.append(subRef)

        let subProducts = PBXGroup(children: [], sourceTree: .group, name: "Products")
        consumer.pbxproj.add(object: subProducts)

        rootObject.projects.append(["ProductGroup": subProducts, "ProjectRef": subRef])

        try consumer.write(path: consumerPath)

        // Exercise add_dependency for a cross-project target.
        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(consumerPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("SubFramework"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("cross-project dependency 'SubFramework'"))

        // Verify the edge was wired up correctly.
        let reopened = try XcodeProj(path: consumerPath)
        let app = try #require(reopened.pbxproj.nativeTargets.first { $0.name == "App" })
        #expect(app.dependencies.count == 1)
        let dep = app.dependencies[0]
        #expect(dep.name == "SubFramework")
        #expect(dep.target == nil)
        let proxy = try #require(dep.targetProxy)
        #expect(proxy.proxyType == .nativeTarget)
        #expect(proxy.remoteInfo == "SubFramework")

        if case let .string(uuid) = proxy.remoteGlobalID {
            #expect(uuid == subTargetUUID)
        } else {
            Issue.record("Expected string remoteGlobalID for cross-project proxy")
        }
        if case let .fileReference(ref) = proxy.containerPortal {
            #expect(ref.path == "SubProject/Sub.xcodeproj")
        } else {
            Issue.record("Expected fileReference containerPortal for cross-project proxy")
        }

        // Calling again is a no-op (already-depends message).
        let again = try tool.execute(arguments: [
            "project_path": Value.string(consumerPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("SubFramework"),
        ])
        guard case let .text(againMessage, _, _) = again.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(againMessage.contains("already depends on"))
    }

    @Test
    func `Add dependency with non-existent dependency`() throws {
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
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("NonExistentFramework"),
        ]

        let result = try tool.execute(arguments: args)

        // Check the result contains not found message
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("not found"))
    }
}
