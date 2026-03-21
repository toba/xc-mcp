import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools
import Foundation

struct SetTestPlanSkippedTagsToolTests {
    let pathUtility = PathUtility(basePath: NSTemporaryDirectory())

    private func createTestPlan(_ json: [String: Any]) throws -> String {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).xctestplan"
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func basePlan() -> [String: Any] {
        [
            "configurations": [[
                "id": "DEFAULT",
                "name": "Default",
                "options": [:] as [String: Any],
            ] as [String: Any]],
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
        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let schema = tool.tool()
        #expect(schema.name == "set_test_plan_skipped_tags")
    }

    @Test
    func `Add tags to plan-level defaults`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".testSuiteFile")]),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))
        #expect(message.contains("plan-level defaults"))

        let json = try TestPlanFile.read(from: path)
        let defaults = json["defaultOptions"] as? [String: Any]
        let skipped = defaults?["skippedTags"] as? [String: Any]
        let tags = skipped?["tags"] as? [String]
        #expect(tags == [".api", ".testSuiteFile"])
        #expect(skipped?["mode"] as? String == "or")
    }

    @Test
    func `Add tags to specific target`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "target_name": .string("AppTests"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("target 'AppTests'"))

        // Per-target should NOT have "mode" key
        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]]
        let skipped = targets?.first?["skippedTags"] as? [String: Any]
        let tags = skipped?["tags"] as? [String]
        #expect(tags == [".api"])
        #expect(skipped?["mode"] == nil)
    }

    @Test
    func `Remove tags from plan-level defaults`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTags"] = [
            "mode": "or",
            "tags": [".api", ".testSuiteFile", ".slow"],
        ] as [String: Any]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".testSuiteFile")]),
            "action": .string("remove"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Removed"))

        let json = try TestPlanFile.read(from: path)
        let skipped = (json["defaultOptions"] as? [String: Any])?["skippedTags"] as? [String: Any]
        let tags = skipped?["tags"] as? [String]
        #expect(tags == [".slow"])
    }

    @Test
    func `Remove all tags clears skippedTags key`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTags"] = [
            "mode": "or",
            "tags": [".api"],
        ] as [String: Any]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "action": .string("remove"),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let skipped = (json["defaultOptions"] as? [String: Any])?["skippedTags"]
        #expect(skipped == nil)
    }

    @Test
    func `Add duplicate tags is idempotent`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"] as? [String: Any])
        defaults["skippedTags"] = [
            "mode": "or",
            "tags": [".api"],
        ] as [String: Any]
        plan["defaultOptions"] = defaults

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".slow")]),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tags =
            ((json["defaultOptions"] as? [
                String: Any
            ])?["skippedTags"] as? [String: Any])?["tags"] as? [String]
        #expect(tags == [".api", ".slow"])
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "target_name": .string("NonExistent"),
        ]
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }

    @Test
    func `Empty tags array throws error`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([]),
        ]
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: args)
        }
    }
}
