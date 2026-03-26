import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct ListGroupsToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("ListGroupsToolTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "list_groups")
        #expect(
            tool.tool().description
                ==
                "List all groups, folder references, and file system synchronized groups in an Xcode project",
        )

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
            }

            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 1)
                #expect(required.contains(.string("project_path")))
            }
        }
    }

    @Test
    func `Validates required parameters`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Missing project_path
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [:])
        }

        // Invalid parameter types
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.bool(true),
            ])
        }
    }

    @Test
    func `Lists groups from project`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(
                message.contains("Groups, folder references, and synchronized groups in project:"),
            )
            // The default project should contain at least a Products group
            #expect(message.contains("Products"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Lists nested groups correctly`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Load the project and add nested groups
        let xcodeproj = try XcodeProj(path: projectPath)

        // Create a top-level group
        let topLevelGroup = PBXGroup(children: [], sourceTree: .group, name: "TopLevel")
        xcodeproj.pbxproj.add(object: topLevelGroup)

        // Create a nested group
        let nestedGroup = PBXGroup(children: [], sourceTree: .group, name: "Nested")
        xcodeproj.pbxproj.add(object: nestedGroup)
        topLevelGroup.children.append(nestedGroup)

        // Create a deeply nested group
        let deeplyNestedGroup = PBXGroup(children: [], sourceTree: .group, name: "DeeplyNested")
        xcodeproj.pbxproj.add(object: deeplyNestedGroup)
        nestedGroup.children.append(deeplyNestedGroup)

        // Add the top-level group to main group
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(topLevelGroup)
        }

        try xcodeproj.write(path: projectPath)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(
                message.contains("Groups, folder references, and synchronized groups in project:"),
            )
            #expect(message.contains("- TopLevel"))
            #expect(message.contains("- TopLevel/Nested"))
            #expect(message.contains("- TopLevel/Nested/DeeplyNested"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Handles project with no custom groups`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Create a minimal test project
        let projectPath = Path(tempDir) + "MinimalProject.xcodeproj"

        // Create a minimal project structure
        let pbxproj = PBXProj()

        // Create main group with no children except products
        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)

        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)
        mainGroup.children.append(productsGroup)

        // Create build configuration
        let buildConfig = XCBuildConfiguration(name: "Debug")
        pbxproj.add(object: buildConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [buildConfig], defaultConfigurationName: "Debug",
        )
        pbxproj.add(object: configList)

        // Create project
        let project = PBXProject(
            name: "MinimalProject",
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

        // Create workspace and xcodeproj
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: projectPath)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(
                message.contains("Groups, folder references, and synchronized groups in project:"),
            )
            #expect(message.contains("- Products"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func `Fails when project does not exist`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Try to list groups from a non-existent project
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/that/does/not/exist.xcodeproj"),
            ])
        }
    }

    @Test
    func `Handles groups with path but no name`() throws {
        let tool = ListGroupsTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Load the project and add a group with path but no name
        let xcodeproj = try XcodeProj(path: projectPath)

        let groupWithPath = PBXGroup(children: [], sourceTree: .group, path: "Sources")
        xcodeproj.pbxproj.add(object: groupWithPath)

        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(groupWithPath)
        }

        try xcodeproj.write(path: projectPath)

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
        ])

        // Verify the result
        if case let .text(message, _, _) = result.content.first {
            #expect(
                message.contains("Groups, folder references, and synchronized groups in project:"),
            )
            #expect(message.contains("- Sources"))
        } else {
            Issue.record("Expected text result")
        }
    }
}
