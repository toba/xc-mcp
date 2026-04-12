import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Test case for missing parameter validation
struct AddFileMissingParamTestCase {
    let description: String
    let arguments: [String: Value]

    init(_ description: String, _ arguments: [String: Value]) {
        self.description = description
        self.arguments = arguments
    }
}

struct AddFileToolTests {
    @Test
    func `Tool creation`() {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "add_file")
        #expect(toolDefinition.description == "Add a file to an Xcode project")
    }

    static let missingParamCases: [AddFileMissingParamTestCase] = [
        AddFileMissingParamTestCase(
            "Missing project_path",
            ["file_path": Value.string("test.swift")],
        ),
        AddFileMissingParamTestCase(
            "Missing file_path",
            ["project_path": Value.string("/path/to/project.xcodeproj")],
        ),
    ]

    @Test(arguments: missingParamCases)
    func `Add file with missing parameter`(_ testCase: AddFileMissingParamTestCase) throws {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: testCase.arguments)
        }
    }

    @Test
    func `Add file with invalid project path`() throws {
        let tool = AddFileTool(pathUtility: PathUtility(basePath: "/tmp"))
        let arguments: [String: Value] = [
            "project_path": Value.string("/nonexistent/path.xcodeproj"),
            "file_path": Value.string("test.swift"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }

    @Test
    func `Add file to main group`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a file
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)
    }

    @Test
    func `Add file to group`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Add a file to "Tests" group
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "group_name": Value.string("Tests"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)
    }

    @Test
    func `Add file to target`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project with a target
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "TestApp", at: projectPath,
        )

        // Add a Swift file to target
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "target_name": Value.string("TestApp"),
        ]

        let result = try tool.execute(arguments: arguments)

        #expect(result.content.count == 1)
        if case let .text(content, _, _) = result.content[0] {
            #expect(content.contains("Successfully added file 'file.swift' to target 'TestApp'"))
        } else {
            Issue.record("Expected text content")
        }

        // Verify file was added to project and target
        let xcodeproj = try XcodeProj(path: projectPath)
        let fileReferences = xcodeproj.pbxproj.fileReferences
        let addedFile = fileReferences.first { $0.name == "file.swift" }
        #expect(addedFile != nil)

        // Verify file was added to target's sources build phase
        let target = xcodeproj.pbxproj.nativeTargets.first { $0.name == "TestApp" }
        #expect(target != nil)

        let sourcesBuildPhase =
            target?.buildPhases.first { $0 is PBXSourcesBuildPhase } as? PBXSourcesBuildPhase
        #expect(sourcesBuildPhase != nil)

        let buildFile = sourcesBuildPhase?.files?.first { $0.file == addedFile }
        #expect(buildFile != nil)
    }

    @Test
    func `Add file to group with path computes relative path correctly`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create project with a group hierarchy: mainGroup -> AppGroup (path: "App") -> ModelsGroup (path: "Models")
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        let pbxproj = PBXProj()

        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        let appGroup = PBXGroup(children: [], sourceTree: .group, name: "App", path: "App")
        pbxproj.add(object: appGroup)
        mainGroup.children.append(appGroup)

        let modelsGroup = PBXGroup(children: [], sourceTree: .group, name: "Models", path: "Models")
        pbxproj.add(object: modelsGroup)
        appGroup.children.append(modelsGroup)

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)
        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
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

        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: projectPath)

        // Create the actual file on disk
        let fileDir = tempDir.appendingPathComponent("App/Models")
        try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
        let filePath = fileDir.appendingPathComponent("AppModel.swift")
        try "// test".write(to: filePath, atomically: true, encoding: .utf8)

        // Add file to the Models group
        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(filePath.path),
            "group_name": Value.string("App/Models"),
        ]

        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added file 'AppModel.swift'"))

        // Verify the file reference path is relative to the group, NOT the project root.
        // Bug was: path = "App/Models/AppModel.swift" (relative to project root)
        // With sourceTree=group under a group at App/Models, Xcode would resolve to App/Models/App/Models/AppModel.swift
        // Fixed: path = "AppModel.swift" (relative to the group's own location)
        let reloadedProj = try XcodeProj(path: projectPath)
        let fileRef = reloadedProj.pbxproj.fileReferences.first { $0.name == "AppModel.swift" }
        #expect(fileRef != nil)
        #expect(
            fileRef?.path == "AppModel.swift",
            "Path should be relative to group, got: \(fileRef?.path ?? "nil")",
        )
    }

    @Test
    func `Add file outside group uses sourceRoot to avoid path doubling`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Reproduce the Swiftiomatic scenario:
        // mainGroup -> AppGroup (name only, no path) -> ViewsGroup (path: "Views")
        // File is at AppGroup/Views/AboutTab.swift, but group fullPath resolves to just "Views"
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        let pbxproj = PBXProj()

        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        // AppGroup has name but NO path — it's a virtual grouping
        let appGroup = PBXGroup(children: [], sourceTree: .group, name: "SwiftiomaticApp")
        pbxproj.add(object: appGroup)
        mainGroup.children.append(appGroup)

        let viewsGroup = PBXGroup(children: [], sourceTree: .group, name: "Views", path: "Views")
        pbxproj.add(object: viewsGroup)
        appGroup.children.append(viewsGroup)

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)
        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
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

        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        let xcodeproj = XcodeProj(workspace: workspace, pbxproj: pbxproj)
        try xcodeproj.write(path: projectPath)

        // File is at SwiftiomaticApp/Views/AboutTab.swift (not under Views/)
        let fileDir = tempDir.appendingPathComponent("SwiftiomaticApp/Views")
        try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
        let filePath = fileDir.appendingPathComponent("AboutTab.swift")
        try "// test".write(to: filePath, atomically: true, encoding: .utf8)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(filePath.path),
            "group_name": Value.string("SwiftiomaticApp/Views"),
        ]

        let result = try tool.execute(arguments: args)
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added file 'AboutTab.swift'"))

        // The file is NOT under the group's fullPath (Views/), so it should use sourceRoot
        // to avoid Xcode resolving Views/ + SwiftiomaticApp/Views/AboutTab.swift
        let reloadedProj = try XcodeProj(path: projectPath)
        let fileRef = reloadedProj.pbxproj.fileReferences.first { $0.name == "AboutTab.swift" }
        #expect(fileRef != nil)
        #expect(
            fileRef?.sourceTree == .sourceRoot,
            "sourceTree should be sourceRoot when file is outside group, got: \(String(describing: fileRef?.sourceTree))",
        )
        #expect(
            fileRef?.path == "SwiftiomaticApp/Views/AboutTab.swift",
            "Path should be relative to project root, got: \(fileRef?.path ?? "nil")",
        )
    }

    @Test
    func `Add file to slash-separated group path`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create project with Components/TableView group hierarchy
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        let pbxproj = PBXProj()

        let mainGroup = PBXGroup(sourceTree: .group)
        pbxproj.add(object: mainGroup)
        let productsGroup = PBXGroup(children: [], sourceTree: .group, name: "Products")
        pbxproj.add(object: productsGroup)

        let componentsGroup = PBXGroup(
            children: [], sourceTree: .group, name: "Components", path: "Components",
        )
        pbxproj.add(object: componentsGroup)
        mainGroup.children.append(componentsGroup)

        let tableViewGroup = PBXGroup(
            children: [], sourceTree: .group, name: "TableView", path: "TableView",
        )
        pbxproj.add(object: tableViewGroup)
        componentsGroup.children.append(tableViewGroup)

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: [:])
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: [:])
        pbxproj.add(object: debugConfig)
        pbxproj.add(object: releaseConfig)
        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
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

        // Create the file on disk
        let fileDir = tempDir.appendingPathComponent("Components/TableView")
        try FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true)
        let filePath = fileDir.appendingPathComponent("TableViewCell.swift")
        try "// test".write(to: filePath, atomically: true, encoding: .utf8)

        // Add file using slash-separated path
        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(filePath.path),
            "group_name": Value.string("Components/TableView"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("Successfully added file 'TableViewCell.swift'"))

        // Verify file is in the TableView group
        let reloaded = try XcodeProj(path: projectPath)
        let tvGroup = reloaded.pbxproj.groups.first { $0.name == "TableView" }
        let childNames = tvGroup?.children.compactMap { ($0 as? PBXFileReference)?.name } ?? []
        #expect(childNames.contains("TableViewCell.swift"))
    }

    @Test
    func `Add file does not create duplicate file references`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create the file on disk
        let filePath = tempDir.appendingPathComponent("file.swift")
        try "// test".write(to: filePath, atomically: true, encoding: .utf8)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        let args: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(filePath.path),
        ]

        // Add the same file twice
        _ = try tool.execute(arguments: args)
        _ = try tool.execute(arguments: args)

        // Should have exactly one PBXFileReference for file.swift
        let reloadedProj = try XcodeProj(path: projectPath)
        let fileRefs = reloadedProj.pbxproj.fileReferences.filter { $0.name == "file.swift" }
        #expect(
            fileRefs.count == 1,
            "Should have exactly 1 file reference, got \(fileRefs.count)",
        )
    }

    @Test
    func `Add xcassets sets lastKnownFileType to folder assetcatalog`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Create an .xcassets directory on disk
        let assetsPath = tempDir.appendingPathComponent("Assets.xcassets")
        try FileManager.default.createDirectory(at: assetsPath, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(assetsPath.path),
        ])

        let reloadedProj = try XcodeProj(path: projectPath)
        let fileRef = reloadedProj.pbxproj.fileReferences.first { $0.name == "Assets.xcassets" }
        #expect(fileRef != nil)
        #expect(
            fileRef?.lastKnownFileType == "folder.assetcatalog",
            "lastKnownFileType should be folder.assetcatalog, got: \(fileRef?.lastKnownFileType ?? "nil")",
        )
    }

    @Test
    func `Add swift file sets lastKnownFileType to sourcecode swift`() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        let filePath = tempDir.appendingPathComponent("Model.swift")
        try "// test".write(to: filePath, atomically: true, encoding: .utf8)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(filePath.path),
        ])

        let reloadedProj = try XcodeProj(path: projectPath)
        let fileRef = reloadedProj.pbxproj.fileReferences.first { $0.name == "Model.swift" }
        #expect(fileRef != nil)
        #expect(
            fileRef?.lastKnownFileType == "sourcecode.swift",
            "lastKnownFileType should be sourcecode.swift, got: \(fileRef?.lastKnownFileType ?? "nil")",
        )
    }

    @Test
    func `Add file with nonexistent target`() throws {
        // Create a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tool = AddFileTool(pathUtility: PathUtility(basePath: tempDir.path))
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Create a test project
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)

        // Try to add file to non-existent target
        let arguments: [String: Value] = [
            "project_path": Value.string(projectPath.string),
            "file_path": Value.string(tempDir.appendingPathComponent("file.swift").path),
            "target_name": Value.string("NonexistentTarget"),
        ]

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: arguments)
        }
    }
}
