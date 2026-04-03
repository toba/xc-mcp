import MCP
import PathKit
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct AddTargetToTestPlanToolTests {
    let pathUtility = PathUtility(basePath: "/")

    /// Creates a temporary directory with a test project containing a test target.
    /// Returns (projectPath, cleanup).
    private func createTempProject() throws -> (String, @Sendable () -> Void) {
        let tmpDir = NSTemporaryDirectory() + "testplan_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir, withIntermediateDirectories: true,
        )
        let projectPath = Path(tmpDir) + "Test.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "Test", targetName: "TestTarget", at: projectPath,
        )
        let cleanup: @Sendable () -> Void = {
            try? FileManager.default.removeItem(atPath: tmpDir)
        }
        return (projectPath.string, cleanup)
    }

    private func createTestPlan(_ json: [String: Any]) throws -> String {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).xctestplan"
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func emptyPlan() -> [String: Any] {
        [
            "configurations": [
                [
                    "id": "DEFAULT",
                    "name": "Default",
                    "options": [:] as [String: Any],
                ] as [String: Any],
            ],
            "defaultOptions": [:] as [String: Any],
            "testTargets": [] as [[String: Any]],
            "version": 1,
        ]
    }

    @Test func `adds target without selectedTests`() throws {
        let (projectPath, cleanup) = try createTempProject()
        defer { cleanup() }
        let path = try createTestPlan(emptyPlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]] ?? []
        #expect(targets.count == 1)
        #expect(targets[0]["selectedTests"] == nil)
    }

    @Test func `adds target with xctest_classes`() throws {
        let (projectPath, cleanup) = try createTempProject()
        defer { cleanup() }
        let path = try createTestPlan(emptyPlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([
                .object([
                    "name": .string("URLRequestTests"),
                ]),
                .object([
                    "name": .string("SessionTests"),
                    "xctest_methods": .array([
                        .string("testInit()"),
                    ]),
                ]),
            ]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]] ?? []
        #expect(targets.count == 1)

        let selected = targets[0]["selectedTests"] as? [String: Any]
        #expect(selected != nil)

        let classes = selected?["xctestClasses"] as? [[String: Any]] ?? []
        #expect(classes.count == 2)
        #expect(classes[0]["name"] as? String == "URLRequestTests")
        #expect(classes[0]["xctestMethods"] == nil)
        #expect(classes[1]["name"] as? String == "SessionTests")

        let methods = classes[1]["xctestMethods"] as? [String] ?? []
        #expect(methods == ["testInit()"])
    }

    @Test func `adds target with suites`() throws {
        let (projectPath, cleanup) = try createTempProject()
        defer { cleanup() }
        let path = try createTestPlan(emptyPlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "suites": .array([
                .object([
                    "name": .string("NetworkTests"),
                    "test_functions": .array([
                        .string("fetchKeys()"),
                        .string("keys()"),
                    ]),
                ]),
                .object([
                    "name": .string("CacheTests"),
                ]),
            ]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]] ?? []
        let selected = targets[0]["selectedTests"] as? [String: Any]
        #expect(selected != nil)

        let suites = selected?["suites"] as? [[String: Any]] ?? []
        #expect(suites.count == 2)
        #expect(suites[0]["name"] as? String == "NetworkTests")

        let funcs = suites[0]["testFunctions"] as? [String] ?? []
        #expect(funcs == ["fetchKeys()", "keys()"])
        #expect(suites[1]["name"] as? String == "CacheTests")
        #expect(suites[1]["testFunctions"] == nil)
    }

    @Test func `adds target with both xctest_classes and suites`() throws {
        let (projectPath, cleanup) = try createTempProject()
        defer { cleanup() }
        let path = try createTestPlan(emptyPlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([
                .object(["name": .string("PerfTests")]),
            ]),
            "suites": .array([
                .object(["name": .string("APISuite")]),
            ]),
        ])

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]] ?? []
        let selected = targets[0]["selectedTests"] as? [String: Any]
        #expect(selected != nil)

        let classes = selected?["xctestClasses"] as? [[String: Any]] ?? []
        let suites = selected?["suites"] as? [[String: Any]] ?? []
        #expect(classes.count == 1)
        #expect(suites.count == 1)
    }

    @Test func `selectedTests roundtrips through JSON`() throws {
        let (projectPath, cleanup) = try createTempProject()
        defer { cleanup() }
        let path = try createTestPlan(emptyPlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = AddTargetToTestPlanTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath),
            "test_plan_path": .string(path),
            "target_name": .string("TestTarget"),
            "xctest_classes": .array([
                .object([
                    "name": .string("DecoderTests"),
                    "xctest_methods": .array([.string("testDecode()")]),
                ]),
            ]),
            "suites": .array([
                .object([
                    "name": .string("ParserTests"),
                    "test_functions": .array([.string("parse()")]),
                ]),
            ]),
        ])

        // Read raw JSON data to verify it's valid xctestplan format
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let rawJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(rawJSON != nil)

        let targets = rawJSON?["testTargets"] as? [[String: Any]] ?? []
        let selected = targets[0]["selectedTests"] as? [String: Any]
        #expect(selected?["xctestClasses"] != nil)
        #expect(selected?["suites"] != nil)
    }
}
