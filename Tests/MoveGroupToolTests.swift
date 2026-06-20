import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct MoveGroupToolTests {
    @Test
    func `Tool creation`() {
        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "move_group")
        #expect(toolDefinition.description?.contains("Move") == true)
    }

    @Test
    func `Missing required parameters fails`() {
        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["project_path": Value.string("/tmp/Test.xcodeproj")])
        }
    }

    @Test
    func `Move sibling group under another group`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Build a sibling layout: Foo and FooTests at root.
        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let foo = PBXGroup(sourceTree: .group, name: "Foo")
        let fooTests = PBXGroup(sourceTree: .group, name: "FooTests")
        xcodeproj.pbxproj.add(object: foo)
        xcodeproj.pbxproj.add(object: fooTests)
        mainGroup.children.append(contentsOf: [foo, fooTests])
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("FooTests"),
            "new_parent": Value.string("Foo"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let reloadedMain = try #require(try reloaded.pbxproj.rootProject()?.mainGroup)
        let rootNames = reloadedMain.children.compactMap { ($0 as? PBXGroup)?.name }
        #expect(rootNames.contains("Foo"))
        #expect(!rootNames.contains("FooTests"))

        let reloadedFoo = try #require(
            reloadedMain.children.compactMap { $0 as? PBXGroup }.first { $0.name == "Foo" })
        let childNames = reloadedFoo.children.compactMap { ($0 as? PBXGroup)?.name }
        #expect(childNames.contains("FooTests"))
    }

    @Test
    func `Move with path rewrite`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let bar = PBXGroup(sourceTree: .group, name: "Bar", path: "Bar/Original")
        xcodeproj.pbxproj.add(object: bar)
        mainGroup.children.append(bar)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("Bar"),
            "new_path": Value.string("Rewritten"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let reloadedBar = try #require(reloaded.pbxproj.groups.first { $0.name == "Bar" })
        #expect(reloadedBar.path == "Rewritten")
    }

    @Test
    func `Move to main group when new_parent is omitted`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let parent = PBXGroup(sourceTree: .group, name: "Parent")
        let child = PBXGroup(sourceTree: .group, name: "Child")
        xcodeproj.pbxproj.add(object: parent)
        xcodeproj.pbxproj.add(object: child)
        parent.children.append(child)
        mainGroup.children.append(parent)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("Parent/Child"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let reloadedMain = try #require(try reloaded.pbxproj.rootProject()?.mainGroup)
        let rootNames = reloadedMain.children.compactMap { ($0 as? PBXGroup)?.name }
        #expect(rootNames.contains("Child"))
        let reloadedParent = try #require(
            reloadedMain.children.compactMap { $0 as? PBXGroup }.first { $0.name == "Parent" })
        #expect(reloadedParent.children.isEmpty)
    }

    @Test
    func `Moving a group under itself fails`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let outer = PBXGroup(sourceTree: .group, name: "Outer")
        let inner = PBXGroup(sourceTree: .group, name: "Inner")
        xcodeproj.pbxproj.add(object: outer)
        xcodeproj.pbxproj.add(object: inner)
        outer.children.append(inner)
        mainGroup.children.append(outer)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "group_path": Value.string("Outer"),
                "new_parent": Value.string("Outer/Inner"),
            ])
        }
    }

    @Test
    func `Missing group reports error`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPath.string),
                "group_path": Value.string("Nope"),
            ])
        }
    }

    @Test
    func `Re-pathing a parent preserves child synchronized-folder resolution`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // mainGroup → Module (path "Old") → Sources (sync, path "Sources"). The sync folder
        // resolves on disk to "Old/Sources".
        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let module = PBXGroup(sourceTree: .group, name: "Module", path: "Old")
        let sources = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "Sources", name: "Sources",
        )
        xcodeproj.pbxproj.add(object: module)
        xcodeproj.pbxproj.add(object: sources)
        module.children.append(sources)
        mainGroup.children.append(module)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("Module"),
            "new_path": Value.string("New"),
        ])
        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("preserved 1 child synchronized folder path"))

        // The sync folder must still resolve to its original on-disk location even though the
        // parent's path attribute changed from "Old" to "New".
        let reloaded = try XcodeProj(path: projectPath)
        let reloadedMain = try #require(try reloaded.pbxproj.rootProject()?.mainGroup)
        let resolutions = OnDiskPath.syncResolutions(in: reloadedMain)
        let sync = try #require(resolutions.values.first { $0.group.name == "Sources" })
        #expect(sync.resolved == "Old/Sources")
        #expect(sync.group.path == "../Old/Sources")
    }

    @Test
    func `Fixing a doubled parent path rewrites child to a clean leaf`() throws {
        let (tempDir, projectPath) = try makeTempProject()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Reproduce the reported broken state: a "Module" group whose path doubled the parent
        // prefix ("Integrations/Module" under an "Integrations" parent), so its accumulated path is
        // "Integrations/Integrations/Module". The Sources sync folder was wired to still resolve to
        // the real "Integrations/Module/Sources" directory.
        let xcodeproj = try XcodeProj(path: projectPath)
        let mainGroup = try #require(try xcodeproj.pbxproj.rootProject()?.mainGroup)
        let integrations = PBXGroup(sourceTree: .group, name: "Integrations", path: "Integrations")
        let module = PBXGroup(sourceTree: .group, name: "Module", path: "Integrations/Module")
        let sources = PBXFileSystemSynchronizedRootGroup(
            sourceTree: .group, path: "../../Module/Sources", name: "Sources",
        )
        xcodeproj.pbxproj.add(object: integrations)
        xcodeproj.pbxproj.add(object: module)
        xcodeproj.pbxproj.add(object: sources)
        module.children.append(sources)
        integrations.children.append(module)
        mainGroup.children.append(integrations)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        // Fix the parent's path so its accumulated path is "Integrations/Module".
        let tool = MoveGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "group_path": Value.string("Integrations/Module"),
            "new_parent": Value.string("Integrations"),
            "new_path": Value.string("Module"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        let reloadedMain = try #require(try reloaded.pbxproj.rootProject()?.mainGroup)
        let resolutions = OnDiskPath.syncResolutions(in: reloadedMain)
        let sync = try #require(resolutions.values.first { $0.group.name == "Sources" })
        // On-disk resolution preserved, and the child path collapsed to a clean "Sources".
        #expect(sync.resolved == "Integrations/Module/Sources")
        #expect(sync.group.path == "Sources")
    }

    private func makeTempProject() throws -> (URL, Path) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProject(name: "TestProject", at: projectPath)
        return (tempDir, projectPath)
    }
}
