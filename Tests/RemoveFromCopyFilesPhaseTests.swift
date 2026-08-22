import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct RemoveFromCopyFilesPhaseTests {
    /// Builds a project whose `App` target has one named Copy Files phase holding `entries`.
    static func makeProject(
        in tempDir: URL,
        phaseName: String = "Embed Frameworks",
        entries: [String] = ["GRDB.framework", "Other.framework", "Third.framework"],
    ) throws -> Path {
        let projectPath = Path(tempDir.path) + "Consumer.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Consumer", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let pbxproj = xcodeproj.pbxproj
        let app = pbxproj.nativeTargets.first { $0.name == "App" }!

        let phase = PBXCopyFilesBuildPhase(
            dstPath: "", dstSubfolderSpec: .frameworks, name: phaseName,
        )
        pbxproj.add(object: phase)
        app.buildPhases.append(phase)

        for entry in entries {
            let fileRef = PBXFileReference(
                sourceTree: .group,
                name: entry,
                lastKnownFileType: "wrapper.framework",
                path: "Frameworks/\(entry)",
            )
            pbxproj.add(object: fileRef)
            pbxproj.rootObject!.mainGroup.children.append(fileRef)
            let buildFile = PBXBuildFile(file: fileRef)
            pbxproj.add(object: buildFile)
            phase.files?.append(buildFile)
        }

        try xcodeproj.write(path: projectPath)
        return projectPath
    }

    static func text(_ result: CallTool.Result) throws -> String {
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }

    @Test
    func `Tool metadata`() {
        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp")).tool()
        #expect(tool.name == "remove_from_copy_files_phase")
    }

    @Test
    func `Missing parameters throw`() throws {
        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: "/tmp"))
        #expect(throws: MCPError.self) { try tool.execute(arguments: [:]) }
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("/x.xcodeproj"), "target_name": .string("App"),
            ])
        }
    }

    @Test
    func `Removes one entry and keeps the phase`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Embed Frameworks"),
            "file_name": .string("GRDB.framework"),
        ]))
        #expect(message.contains("Removed 1 entry"))
        #expect(message.contains("2 entries remain"))

        let reloaded = try XcodeProj(path: projectPath)
        let app = reloaded.pbxproj.nativeTargets.first { $0.name == "App" }!
        let phase = app.buildPhases.compactMap { $0 as? PBXCopyFilesBuildPhase }.first
        #expect(phase != nil)
        let names = (phase?.files ?? []).compactMap { $0.file?.name }
        #expect(names == ["Other.framework", "Third.framework"])
    }

    @Test
    func `Leaves the file reference in the project`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("GRDB.framework"),
        ])

        let reloaded = try XcodeProj(path: projectPath)
        #expect(reloaded.pbxproj.fileReferences.contains { $0.name == "GRDB.framework" })
    }

    @Test
    func `Matches by full path`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("Frameworks/Other.framework"),
        ]))
        #expect(message.contains("Removed 1 entry"))
    }

    @Test
    func `Lists the phase entries when the name does not match`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "file_name": .string("Ghost.framework"),
        ]))
        #expect(message.contains("is not in Copy Files phase"))
        #expect(message.contains("Frameworks/GRDB.framework"))
    }

    @Test
    func `Reports a missing target`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        let message = try Self.text(tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("Ghost"),
            "file_name": .string("GRDB.framework"),
        ]))
        #expect(message.contains("not found in project"))
    }

    @Test
    func `Requires disambiguation when the target has two copy files phases`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = try Self.makeProject(in: tempDir)

        let xcodeproj = try XcodeProj(path: projectPath)
        let app = xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" }!
        let second = PBXCopyFilesBuildPhase(
            dstPath: "docx", dstSubfolderSpec: .resources, name: "Copy Docs",
        )
        xcodeproj.pbxproj.add(object: second)
        app.buildPhases.append(second)
        try xcodeproj.write(path: projectPath)

        let tool = RemoveFromCopyFilesPhase(pathUtility: PathUtility(basePath: tempDir.path))
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "file_name": .string("GRDB.framework"),
            ])
        }
    }
}
