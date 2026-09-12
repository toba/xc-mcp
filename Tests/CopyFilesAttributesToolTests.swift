import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct CopyFilesAttributesToolTests {
    /// Builds a project whose App target holds an Embed Helpers phase with two flagged entries.
    private func makeProject(at dir: URL) throws -> Path {
        let projectPath = Path(dir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = PBXCopyFilesBuildPhase(
            dstPath: "Contents/Helpers", dstSubfolderSpec: .wrapper, name: "Embed Helpers",
        )
        xcodeproj.pbxproj.add(object: phase)
        target.buildPhases.append(phase)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let paths = PathUtility(basePath: dir.path)

        for name in ["helper-one", "helper-two"] {
            let filePath = dir.appendingPathComponent(name).path
            try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
            _ = try AddFileTool(pathUtility: paths).execute(arguments: [
                "project_path": .string(projectPath.string),
                "file_path": .string(filePath),
            ])
        }

        _ = try AddToCopyFilesPhase(pathUtility: paths).execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Embed Helpers"),
            "files": .array([.string("helper-one"), .string("helper-two")]),
            "attributes": .array([.string("CodeSignOnCopy")]),
        ])
        return projectPath
    }

    /// The entries of the App target's only Copy Files phase, in order.
    private func entries(of projectPath: Path) throws -> [PBXBuildFile] {
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(
            target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        return phase.files ?? []
    }

    @Test
    func `Tool creation`() {
        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: "/tmp"))
        let toolDefinition = tool.tool()

        #expect(toolDefinition.name == "set_copy_files_attributes")
        #expect(toolDefinition.description?.contains("CodeSignOnCopy") == true)
    }

    @Test
    func `Missing required params throws`() {
        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "target_name": Value.string("App"),
                "file_name": Value.string("helper-one"),
                "attributes": Value.array([]),
            ])
        }

        // attributes is required, and an absent key is not an empty list.
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "file_name": Value.string("helper-one"),
            ])
        }
    }

    @Test
    func `An unknown attribute throws`() {
        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: "/tmp"))

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": Value.string("/path/to/project.xcodeproj"),
                "target_name": Value.string("App"),
                "file_name": Value.string("helper-one"),
                "attributes": Value.array([.string("CodeSign")]),
            ])
        }
    }

    @Test
    func `list_copy_files_phases reports each entry's attributes`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ]))

        #expect(text.contains("helper-one  attributes: [CodeSignOnCopy]"))
        #expect(text.contains("helper-two  attributes: [CodeSignOnCopy]"))
    }

    @Test
    func `list_copy_files_phases reports an entry that carries no attributes`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let setTool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try setTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([]),
        ])

        let listTool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ]))

        #expect(text.contains("helper-one  attributes: (none)"))
        #expect(text.contains("helper-two  attributes: [CodeSignOnCopy]"))
    }

    @Test
    func `list_copy_files_phases reports each entry's platform filters`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let filterTool = SetPlatformFiltersTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try filterTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "platform_filters": .array([.string("macos")]),
        ])

        let listTool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ]))

        #expect(text.contains("helper-one  attributes: [CodeSignOnCopy]  platforms: [macos]"))
        #expect(text.contains("helper-two  attributes: [CodeSignOnCopy]  platforms: (none)"))
    }

    @Test
    func `Both set tools answer an unknown entry with the same text`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)
        let paths = PathUtility(basePath: tempDir.path)

        let attributesText = try message(
            of: SetCopyFilesAttributesTool(pathUtility: paths)
                .execute(arguments: [
                    "project_path": .string(projectPath.string),
                    "target_name": .string("App"),
                    "file_name": .string("helper-three"),
                    "attributes": .array([.string("CodeSignOnCopy")]),
                ]))

        let filtersText = try message(
            of: SetPlatformFiltersTool(pathUtility: paths)
                .execute(arguments: [
                    "project_path": .string(projectPath.string),
                    "target_name": .string("App"),
                    "file_name": .string("helper-three"),
                    "platform_filters": .array([.string("macos")]),
                ]))

        #expect(attributesText == filtersText)
        #expect(attributesText.contains("is not in Copy Files phase 'Embed Helpers'"))
    }

    @Test
    func `add_to_copy_files_phase reaches an unnamed phase through dst_path`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)
        let paths = PathUtility(basePath: tempDir.path)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let unnamed = PBXCopyFilesBuildPhase(
            dstPath: "Contents/Extras", dstSubfolderSpec: .wrapper, name: nil,
        )
        xcodeproj.pbxproj.add(object: unnamed)
        target.buildPhases.append(unnamed)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let text = try message(
            of: AddToCopyFilesPhase(pathUtility: paths).execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "dst_path": .string("Contents/Extras"),
                "files": .array([.string("helper-one")]),
            ]))

        #expect(text.contains("dstPath=Contents/Extras"))

        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(
            updatedTarget.buildPhases
                .compactMap { $0 as? PBXCopyFilesBuildPhase }
                .first { $0.dstPath == "Contents/Extras" })
        #expect(phase.files?.count == 1)
    }

    @Test
    func `add_to_copy_files_phase refuses a phase name that matches two phases`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)
        let paths = PathUtility(basePath: tempDir.path)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let duplicate = PBXCopyFilesBuildPhase(
            dstPath: "Contents/Extras", dstSubfolderSpec: .wrapper, name: "Embed Helpers",
        )
        xcodeproj.pbxproj.add(object: duplicate)
        target.buildPhases.append(duplicate)
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        #expect(throws: MCPError.self) {
            try AddToCopyFilesPhase(pathUtility: paths).execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "phase_name": .string("Embed Helpers"),
                "files": .array([.string("helper-one")]),
            ])
        }
    }

    @Test
    func `An empty list clears the attributes`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([]),
        ]))

        #expect(text.contains("[CodeSignOnCopy] -> (none)"))

        let updated = try entries(of: projectPath)
        #expect(BuildFileAttributes.read(updated[0]).isEmpty)
        #expect(updated[0].settings?["ATTRIBUTES"] == nil)
        #expect(BuildFileAttributes.read(updated[1]) == ["CodeSignOnCopy"])
    }

    @Test
    func `A change keeps the entry in place`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let before = try entries(of: projectPath).map { BuildPhaseEntry.label(for: $0) }
        let beforeUUIDs = try entries(of: projectPath).map(\.uuid)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([.string("RemoveHeadersOnCopy")]),
        ])

        let after = try entries(of: projectPath)
        #expect(after.map { BuildPhaseEntry.label(for: $0) } == before)
        #expect(after.map(\.uuid) == beforeUUIDs)
        #expect(BuildFileAttributes.read(after[0]) == ["RemoveHeadersOnCopy"])
    }

    @Test
    func `A caller sets more than one attribute`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-two"),
            "attributes": .array([.string("CodeSignOnCopy"), .string("RemoveHeadersOnCopy")]),
        ])

        let updated = try entries(of: projectPath)
        #expect(BuildFileAttributes.read(updated[1]) == ["CodeSignOnCopy", "RemoveHeadersOnCopy"])
    }

    @Test
    func `An attribute name is spelled the way Xcode writes it`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([.string("removeheadersoncopy")]),
        ])

        let updated = try entries(of: projectPath)
        #expect(BuildFileAttributes.read(updated[0]) == ["RemoveHeadersOnCopy"])
    }

    @Test
    func `A repeated call reports no change`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([.string("CodeSignOnCopy")]),
        ]))

        #expect(text.contains("No changes made"))
    }

    @Test
    func `An unknown entry lists the entries in the phase`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let tool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-three"),
            "attributes": .array([.string("CodeSignOnCopy")]),
        ]))

        #expect(text.contains("is not in Copy Files phase 'Embed Helpers'"))
        #expect(text.contains("helper-one"))
        #expect(text.contains("helper-two"))
    }

    @Test
    func `A bare string attribute reads as a one-element list`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try makeProject(at: tempDir)

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let phase = try #require(
            target.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first)
        let entry = try #require(phase.files?.first)
        entry.settings = ["ATTRIBUTES": .string("CodeSignOnCopy")]
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        let listTool = ListCopyFilesPhases(pathUtility: PathUtility(basePath: tempDir.path))
        let text = try message(of: listTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
        ]))
        #expect(text.contains("helper-one  attributes: [CodeSignOnCopy]"))

        // the same names in list form still count as a change, because the stored shape differs
        let setTool = SetCopyFilesAttributesTool(pathUtility: PathUtility(basePath: tempDir.path))
        let setText = try message(of: setTool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("helper-one"),
            "attributes": .array([.string("CodeSignOnCopy")]),
        ]))
        #expect(setText.contains("[CodeSignOnCopy] -> [CodeSignOnCopy]"))

        let updated = try entries(of: projectPath)
        #expect(updated[0].settings?["ATTRIBUTES"]?.arrayValue == ["CodeSignOnCopy"])
    }
}
