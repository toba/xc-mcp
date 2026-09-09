import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

/// Covers the optimistic-concurrency guard the project-editing tools pass to `PBXProjWriter`.
@Suite(.temporaryDirectory)
struct ProjectWritePreimageTests {
    /// Runs `body` while a concurrent writer appends to the project file, and returns the bytes
    /// that writer left behind.
    ///
    /// The advisory write lock is held for the whole edit, so the tool reads its preimage, reaches
    /// the lock it cannot take, and finds different bytes once the lock frees.
    ///
    /// - Parameters:
    ///   - projectPath: The .xcodeproj bundle the tool edits.
    ///   - body: Calls the tool. It runs on its own task.
    /// - Returns: The project bytes the concurrent writer wrote.
    private static func racingWrite(
        against projectPath: Path,
        body: @escaping @Sendable () throws -> CallTool.Result,
    ) async throws -> Data {
        let pbxprojPath = XcodeProj.pbxprojPath(projectPath).string
        let original = try #require(FileManager.default.contents(atPath: pbxprojPath))

        let lockPath = SafeProjectWrite.lockFilePath(for: projectPath.string)
        let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o644)
        try #require(lockFD >= 0)
        try #require(flock(lockFD, LOCK_EX) == 0)

        let running = Task(name: "tool write behind the lock") { try body() }

        // long enough for the tool to read the project and reach the lock it cannot take, with
        // headroom for a loaded machine
        try await Task.sleep(for: .seconds(5))

        var edited = original
        edited.append(contentsOf: "\n".utf8)
        try edited.write(to: URL(fileURLWithPath: pbxprojPath))

        flock(lockFD, LOCK_UN)
        close(lockFD)

        await #expect(throws: MCPError.self) { try await running.value }
        return edited
    }

    @Test
    func `set_build_setting refuses to write over a concurrent edit`() async throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let projectPathString = projectPath.string
        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        let edited = try await Self.racingWrite(against: projectPath) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPathString),
                "target_name": Value.string("App"),
                "configuration": Value.string("Debug"),
                "setting_name": Value.string("SWIFT_VERSION"),
                "setting_value": Value.string("6.0"),
            ])
        }

        let pbxprojPath = XcodeProj.pbxprojPath(projectPath).string
        #expect(FileManager.default.contents(atPath: pbxprojPath) == edited)
    }

    @Test
    func `create_group refuses to write over a concurrent edit`() async throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let projectPathString = projectPath.string
        let tool = CreateGroupTool(pathUtility: PathUtility(basePath: tempDir.path))
        let edited = try await Self.racingWrite(against: projectPath) {
            try tool.execute(arguments: [
                "project_path": Value.string(projectPathString),
                "group_name": Value.string("Models"),
            ])
        }

        let pbxprojPath = XcodeProj.pbxprojPath(projectPath).string
        #expect(FileManager.default.contents(atPath: pbxprojPath) == edited)
    }
}
