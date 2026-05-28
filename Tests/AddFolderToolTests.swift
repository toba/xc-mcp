import Foundation
import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj

@testable import XCMCPTools

/// Test case for missing parameter validation
struct AddFolderMissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct AddFolderToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("AddFolderToolTests-\(UUID().uuidString)")
            .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func `Tool has correct properties`() {
        let tool = AddFolderTool(pathUtility: pathUtility)

        #expect(tool.tool().name == "add_synchronized_folder")
        #expect(
            tool.tool().description == "Add a synchronized folder reference to an Xcode project",
        )

        let schema = tool.tool().inputSchema
        if case .object(let schemaDict) = schema {
            if case .object(let props) = schemaDict["properties"] {
                #expect(props["project_path"] != nil)
                #expect(props["folder_path"] != nil)
                #expect(props["group_name"] != nil)
                #expect(props["target_name"] != nil)
            }

            if case .array(let required) = schemaDict["required"] {
                #expect(required.count == 2)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("folder_path")))
            }
        }
    }

    static let missingParamCases: [AddFolderMissingParamTestCase] = [
        AddFolderMissingParamTestCase(
            "Missing project_path",
            ["folder_path": .string("path/to/folder")],
        ),
        AddFolderMissingParamTestCase(
            "Missing folder_path",
            ["project_path": .string("project.xcodeproj")],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Validates required parameter`(_ testCase: AddFolderMissingParamTestCase) throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test
    func `Validates invalid parameter type`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.bool(true),
                "folder_path": Value.string("path/to/folder"),
            ])
        }
    }

    @Test
    func `Adds folder reference to project`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(folderPath.string),
        ])

        // Verify the result
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the project was updated
        let updatedProject = try XcodeProj(path: projectPath)
        let folderReferences = updatedProject.pbxproj.fileSystemSynchronizedRootGroups
        #expect(folderReferences.count == 1)
        #expect(folderReferences.first?.name == "TestFolder")
    }

    @Test
    func `Adds folder under group with path strips redundant prefix`() throws {
        // Reproduction for issue bhc-8co: when the parent group has `path = Sync`
        // and the folder lives at `Sync/Sources` on disk, the stored `path`
        // attribute on the synchronized root group should be just `Sources`
        // (relative to its parent), not `Sync/Sources`.
        let tool = AddFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let xcodeproj = try XcodeProj(path: projectPath)
        // Parent group has BOTH a name and a path -- this is the shape that triggers the bug.
        let syncGroup = PBXGroup(sourceTree: .group, name: "Sync", path: "Sync")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        try xcodeproj.write(path: projectPath)

        // Folder lives at <projectDir>/Sync/Sources on disk.
        let folderPath = Path(tempDir) + "Sync" + "Sources"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sync/Sources"),
            "group_name": .string("Sync"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let syncRoot = try #require(
            reloaded.pbxproj.fileSystemSynchronizedRootGroups.first { $0.name == "Sources" },
        )
        #expect(syncRoot.path == "Sources")
    }

    @Test
    func `Adds folder under group with only path set (no name) strips prefix`() throws {
        // Variant of bhc-8co: parent group has `path = Sync` but NO `name`.
        let tool = AddFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let xcodeproj = try XcodeProj(path: projectPath)
        let syncGroup = PBXGroup(sourceTree: .group, path: "Sync")
        xcodeproj.pbxproj.add(object: syncGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(syncGroup)
        }
        try xcodeproj.write(path: projectPath)

        let folderPath = Path(tempDir) + "Sync" + "Sources"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sync/Sources"),
            "group_name": .string("Sync"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let syncRoot = try #require(
            reloaded.pbxproj.fileSystemSynchronizedRootGroups.first { $0.name == "Sources" },
        )
        #expect(syncRoot.path == "Sources")
    }

    @Test
    func `Adds folder under virtual group (name only no path) keeps full path`() throws {
        // A "virtual" group has only `name`, no `path` -- it does NOT add a path
        // component to its children. The synchronized folder's path must remain
        // project-root-relative so files resolve correctly.
        let tool = AddFolderTool(pathUtility: pathUtility)

        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let xcodeproj = try XcodeProj(path: projectPath)
        let virtualGroup = PBXGroup(sourceTree: .group, name: "Modules")
        xcodeproj.pbxproj.add(object: virtualGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(virtualGroup)
        }
        try xcodeproj.write(path: projectPath)

        let folderPath = Path(tempDir) + "Sync" + "Sources"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string("Sync/Sources"),
            "group_name": .string("Modules"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let syncRoot = try #require(
            reloaded.pbxproj.fileSystemSynchronizedRootGroups.first { $0.name == "Sources" },
        )
        // Parent has no on-disk path, so folder path stays relative to project root.
        #expect(syncRoot.path == "Sync/Sources")
    }

    @Test
    func `Adds folder to specific group`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Load the project and add a custom group
        let xcodeproj = try XcodeProj(path: projectPath)
        let customGroup = PBXGroup(children: [], sourceTree: .group, name: "CustomGroup")
        xcodeproj.pbxproj.add(object: customGroup)

        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(customGroup)
        }
        try xcodeproj.write(path: projectPath)

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(folderPath.string),
            "group_name": .string("CustomGroup"),
        ])

        // Verify the result
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
            #expect(message.contains("in group 'CustomGroup'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the folder was added to the correct group
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedCustomGroup = updatedProject.pbxproj.groups.first { $0.name == "CustomGroup" }
        #expect(updatedCustomGroup?.children.count == 1)
    }

    @Test
    func `Adds folder to target`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project with a target
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestTarget", at: projectPath,
        )

        // Create a test folder
        let folderPath = Path(tempDir) + "TestFolder"
        try FileManager.default.createDirectory(
            atPath: folderPath.string, withIntermediateDirectories: true,
        )

        // Execute the tool
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "folder_path": Value.string(folderPath.string),
            "target_name": Value.string("TestTarget"),
        ])

        // Verify the result
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'TestFolder'"))
            #expect(message.contains("to target 'TestTarget'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the folder was added to the target
        let updatedProject = try XcodeProj(path: projectPath)
        let updatedTarget = updatedProject.pbxproj.nativeTargets.first { $0.name == "TestTarget" }
        let resourcesPhase = updatedTarget?.buildPhases.first { $0 is PBXResourcesBuildPhase }
        #expect(resourcesPhase != nil)
    }

    @Test
    func `Fails when folder does not exist`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Try to add a non-existent folder
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string("/path/that/does/not/exist"),
            ])
        }

        // Clean up
        try FileManager.default.removeItem(atPath: projectPath.string)
    }

    @Test
    func `Fails when path is not a directory`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create a file instead of a folder
        let filePath = Path(tempDir) + "TestFile.txt"
        try "test content".write(
            to: URL(filePath: filePath.string), atomically: true, encoding: .utf8,
        )

        // Try to add a file as a folder
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "folder_path": .string(filePath.string),
            ])
        }

        // Clean up
        try FileManager.default.removeItem(atPath: projectPath.string)
        try FileManager.default.removeItem(atPath: filePath.string)
    }

    @Test
    func `Adds folder with path relative to parent group`() throws {
        let tool = AddFolderTool(pathUtility: pathUtility)

        // Create a test project
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create directory structure: DOM/Sources
        let domPath = Path(tempDir) + "DOM"
        let sourcesPath = domPath + "Sources"
        try FileManager.default.createDirectory(
            atPath: sourcesPath.string, withIntermediateDirectories: true,
        )

        // Load the project and add a group "DOM" with path = "DOM"
        let xcodeproj = try XcodeProj(path: projectPath)
        let domGroup = PBXGroup(children: [], sourceTree: .group, name: "DOM", path: "DOM")
        xcodeproj.pbxproj.add(object: domGroup)
        if let mainGroup = try xcodeproj.pbxproj.rootProject()?.mainGroup {
            mainGroup.children.append(domGroup)
        }
        try xcodeproj.write(path: projectPath)

        // Execute the tool to add DOM/Sources to the DOM group
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "folder_path": .string(sourcesPath.string),
            "group_name": .string("DOM"),
        ])

        // Verify the result
        if case .text(let message, _, _) = result.content.first {
            #expect(message.contains("Successfully added folder reference 'Sources'"))
            #expect(message.contains("in group 'DOM'"))
        } else {
            Issue.record("Expected text result")
        }

        // Verify the folder was added with the correct relative path
        // Since the folder is inside DOM group (which has path = "DOM"),
        // the synchronized folder should have path = "Sources" (not "DOM/Sources")
        let updatedProject = try XcodeProj(path: projectPath)
        let folderReferences = updatedProject.pbxproj.fileSystemSynchronizedRootGroups
        #expect(folderReferences.count == 1)

        let folderRef = folderReferences.first
        #expect(folderRef?.name == "Sources")
        // The key assertion: path should be relative to the parent group, not project root
        #expect(
            folderRef?.path == "Sources",
            "Expected path to be 'Sources' relative to DOM group, not 'DOM/Sources'",
        )
    }
}

