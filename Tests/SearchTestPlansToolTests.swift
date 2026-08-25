import MCP
import PathKit
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SearchTestPlansToolTests {
    let pathUtility = PathUtility(basePath: "/")

    private func setup() throws -> (projectPath: String, tmpDir: String) {
        let tmpDir = TemporaryDirectory.path
        let projectPath = (Path(tmpDir) + "Test.xcodeproj").string
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Test", targetName: "TestTarget", at: Path(projectPath),
        )
        return (projectPath, tmpDir)
    }

    private func writePlan(_ json: [String: AnyValue], dir: String, name: String) throws -> String {
        let path = (Path(dir) + "\(name).xctestplan").string
        try TestPlanFile.write(json, to: path)
        return path
    }

    @Test func `matches substring inside string value`() throws {
        let (projectPath, tmpDir) = try setup()

        let plan: [String: AnyValue] = [
            "version": 1,
            "configurations": [
                [
                    "id": "DEFAULT",
                    "name": "Default",
                    "options": ["targetForVariableExpansion": "com.thesisapp.editor"],
                ]
            ],
            "testTargets": [],
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
        let (projectPath, tmpDir) = try setup()

        let plan: [String: AnyValue] = [
            "version": 1,
            "configurations": [["id": "X", "name": "Default"]],
            "testTargets": [],
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
        let (projectPath, tmpDir) = try setup()

        let plan: [String: AnyValue] = [
            "version": 1,
            "testTargets": [["target": ["name": "MyAppTests"]]],
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
