import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct PlatformFiltersToolTests {
    /// Builds a project with an app target, a helper target, and an Embed Helpers copy phase
    /// carrying a file reference named `Helper.app`.
    private func makeProject(at dir: URL) throws -> Path {
        let projectPath = Path(dir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTwoTargets(
            name: "TestProject", target1: "App", target2: "Helper", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let pbxproj = xcodeproj.pbxproj
        let app = try #require(pbxproj.nativeTargets.first { $0.name == "App" })
        let helper = try #require(pbxproj.nativeTargets.first { $0.name == "Helper" })

        let helperProduct = PBXFileReference(sourceTree: .buildProductsDir, path: "Helper.app")
        pbxproj.add(object: helperProduct)
        helper.product = helperProduct

        let phase = PBXCopyFilesBuildPhase(
            dstPath: "", dstSubfolderSpec: .executables, name: "Embed Helpers",
        )
        pbxproj.add(object: phase)
        app.buildPhases.append(phase)

        try PBXProjWriter.write(xcodeproj, to: projectPath)
        return projectPath
    }

    @Test
    func `Tool creation`() {
        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_platform_filters")
        #expect(toolDefinition.description?.contains("platformFilters") == true)
    }

    @Test
    func `Missing required params throws`() {
        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "platform_filters": Value.array([.string("macos")]),
                "dependency_name": Value.string("Helper"),
            ])
        }

        // platform_filters is required, and an absent key is not an empty list.
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "dependency_name": Value.string("Helper"),
            ])
        }
    }

    @Test
    func `Naming both a file and a dependency throws`() {
        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "platform_filters": Value.array([.string("macos")]),
                "file_name": Value.string("Helper.app"),
                "dependency_name": Value.string("Helper"),
            ])
        }
    }

    @Test
    func `Naming neither a file nor a dependency throws`() {
        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "platform_filters": Value.array([.string("macos")]),
            ])
        }
    }

    @Test
    func `An unknown platform name throws`() {
        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "platform_filters": Value.array([.string("mac")]),
                "dependency_name": Value.string("Helper"),
            ])
        }
    }

    @Test
    func `Set platform filters on a copy phase entry`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let addTool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Embed Helpers"),
            "files": Value.array([.string("Helper.app")]),
        ])

        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "file_name": Value.string("Helper.app"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("(none) -> [macos]"))

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(app.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        let entry = try #require(phase.files?.first)
        #expect(entry.platformFilters == ["macos"])
    }

    @Test
    func `Set platform filters on a dependency`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let addTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
        ])

        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let dependency = try #require(app.dependencies.first)
        #expect(dependency.platformFilters == ["macos"])
    }

    @Test
    func `An empty list clears the filters`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let addTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("[macos] -> (none)"))

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let dependency = try #require(app.dependencies.first)
        #expect(dependency.platformFilters == nil)
        #expect(dependency.platformFilter == nil)
    }

    @Test
    func `A repeated call reports no change`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let addTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        let tool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("No changes made"))
    }

    @Test
    func `A platform name is lowercased`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let addTool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try addTool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macOS")]),
        ])

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let dependency = try #require(app.dependencies.first)
        #expect(dependency.platformFilters == ["macos"])
    }

    @Test
    func `add_to_copy_files_phase writes the filters on the new entry`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = AddToCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "phase_name": Value.string("Embed Helpers"),
            "files": Value.array([.string("Helper.app")]),
            "platform_filters": Value.array([.string("macos")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("platformFilters = [macos]"))

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(app.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        let entry = try #require(phase.files?.first)
        #expect(entry.platformFilters == ["macos"])
    }

    @Test
    func `add_dependency writes the filters on the new dependency`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = AddDependencyTool(pathUtility: PathUtility(basePath: tempDir.path))
        let result = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "dependency_name": Value.string("Helper"),
            "platform_filters": Value.array([.string("macos")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text result")
            return
        }
        #expect(message.contains("platformFilters [macos]"))

        let updated = try XcodeProj(path: projectPath)
        let app = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let dependency = try #require(app.dependencies.first)
        #expect(dependency.platformFilters == ["macos"])
    }
}
