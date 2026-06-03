import MCP
import PathKit
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct SearchTestPlansToolTests {
    let pathUtility = PathUtility(basePath: "/")

    private func setup() throws -> (projectPath: String, tmpDir: String, cleanup: @Sendable () -> Void) {
        let tmpDir = NSTemporaryDirectory() + "searchplans_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir, withIntermediateDirectories: true,
        )
        let projectPath = (Path(tmpDir) + "Test.xcodeproj").string
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Test", targetName: "TestTarget", at: Path(projectPath),
        )
        let cleanup: @Sendable () -> Void = {
            try? FileManager.default.removeItem(atPath: tmpDir)
        }
        return (projectPath, tmpDir, cleanup)
    }

    private func writePlan(_ json: [String: Any], dir: String, name: String) throws -> String {
        let path = (Path(dir) + "\(name).xctestplan").string
        try TestPlanFile.write(json, to: path)
        return path
    }

    @Test func `matches substring inside string value`() throws {
        let (projectPath, tmpDir, cleanup) = try setup()
        defer { cleanup() }

        let plan: [String: Any] = [
            "version": 1,
            "configurations": [
                [
                    "id": "DEFAULT",
                    "name": "Default",
                    "options": ["targetForVariableExpansion": "com.thesisapp.editor"],
                ] as [String: Any],
            ],
            "testTargets": [] as [[String: Any]],
        ]
        _ = try writePlan(plan, dir: tmpDir, name: "Hit")

        let tool = SearchTestPlansTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "query": .string("com.thesisapp.editor"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("1 file(s) matched"))
        #expect(message.contains("com.thesisapp.editor"))
        #expect(message.contains("Hit.xctestplan"))
    }

    @Test func `reports no matches when query absent`() throws {
        let (projectPath, tmpDir, cleanup) = try setup()
        defer { cleanup() }

        let plan: [String: Any] = [
            "version": 1,
            "configurations": [["id": "X", "name": "Default"] as [String: Any]],
            "testTargets": [] as [[String: Any]],
        ]
        _ = try writePlan(plan, dir: tmpDir, name: "Empty")

        let tool = SearchTestPlansTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "query": .string("not-in-any-plan"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("no matches"))
    }

    @Test func `case insensitive match`() throws {
        let (projectPath, tmpDir, cleanup) = try setup()
        defer { cleanup() }

        let plan: [String: Any] = [
            "version": 1,
            "testTargets": [
                ["target": ["name": "MyAppTests"] as [String: Any]] as [String: Any],
            ],
        ]
        _ = try writePlan(plan, dir: tmpDir, name: "Plan")

        let tool = SearchTestPlansTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "query": .string("myapp"),
            "case_sensitive": .bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("1 file(s) matched"))
    }
}
