import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct SetTestPlanSkippedTestsToolTests {
    let pathUtility = PathUtility(basePath: NSTemporaryDirectory())

    private func createTestPlan(_ json: [String: Any]) throws -> String {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).xctestplan"
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func basePlan() -> [String: Any] {
        [
            "configurations": [
                [
                    "id": "DEFAULT",
                    "name": "Default",
                    "options": [:] as [String: Any],
                ] as [String: Any],
            ],
            "defaultOptions": [:] as [String: Any],
            "testTargets": [
                [
                    "target": [
                        "containerPath": "container:App.xcodeproj",
                        "identifier": "ABC123",
                        "name": "AppTests",
                    ] as [String: Any],
                ] as [String: Any],
            ],
            "version": 1,
        ]
    }

    @Test
    func `Tool schema has correct name`() {
        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let schema = tool.tool()
        #expect(schema.name == "set_test_plan_skipped_tests")
    }

    @Test
    func `Add tests to plan-level defaults`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([
                .string("PerfTests"),
                .string("XMLDecoderPerformanceTests/testDecode()"),
            ]),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))
        #expect(message.contains("plan-level defaults"))

        let json = try TestPlanFile.read(from: path)
        let defaults = json["defaultOptions"] as? [String: Any]
        let tests = defaults?["skippedTests"] as? [String]
        #expect(tests == ["PerfTests", "XMLDecoderPerformanceTests/testDecode()"])
    }

    @Test
    func `Add tests to specific target`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "target_name": .string("AppTests"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("target 'AppTests'"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]]
        let tests = targets?.first?["skippedTests"] as? [String]
        #expect(tests == ["PerfTests"])
    }

    @Test
    func `Remove tests from plan-level defaults`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTests"] = ["PerfTests", "SlowTests", "FlakyTests"]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests"), .string("SlowTests")]),
            "action": .string("remove"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Removed"))

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"] as? [String: Any])?["skippedTests"] as? [String]
        #expect(tests == ["FlakyTests"])
    }

    @Test
    func `Remove all tests clears skippedTests key`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTests"] = ["PerfTests"]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "action": .string("remove"),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"] as? [String: Any])?["skippedTests"]
        #expect(tests == nil)
    }

    @Test
    func `Add duplicate tests is idempotent`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTests"] = ["PerfTests"]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests"), .string("SlowTests")]),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tests = (json["defaultOptions"] as? [String: Any])?["skippedTests"] as? [String]
        #expect(tests == ["PerfTests", "SlowTests"])
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([.string("PerfTests")]),
            "target_name": .string("NonExistent"),
        ]
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test
    func `Empty tests array throws error`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTestsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tests": .array([]),
        ]
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
