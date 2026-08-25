import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SetTestPlanSkippedTagsToolTests {
    let pathUtility = PathUtility(basePath: TemporaryDirectory.path)

    private func createTestPlan(_ json: [String: AnyValue]) throws -> String {
        let path = TemporaryDirectory.url.appendingPathComponent("test.xctestplan").path
        try TestPlanFile.write(json, to: path)
        return path
    }

    private func basePlan() -> [String: AnyValue] {
        [
            "configurations": [["id": "DEFAULT", "name": "Default", "options": [:]]],
            "defaultOptions": [:],
            "testTargets": [
                [
                    "target": [
                        "containerPath": "container:App.xcodeproj",
                        "identifier": "ABC123",
                        "name": "AppTests",
                    ]
                ]
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

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".testSuiteFile")]),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Added"))
        #expect(message.contains("plan-level defaults"))

        let json = try TestPlanFile.read(from: path)
        let defaults = json["defaultOptions"]?.dictionaryValue
        let skipped = defaults?["skippedTags"]?.dictionaryValue
        let tags = skipped?["tags"]?.stringArrayValue
        #expect(tags == [".api", ".testSuiteFile"])
        #expect(skipped?["mode"]?.stringValue == "or")
    }

    @Test
    func `Add tags to specific target`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "target_name": .string("AppTests"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("target 'AppTests'"))

        // Per-target must have "mode" — without it Xcode defaults to AND, which silently no-ops
        // since no test has every listed tag.
        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue
        let skipped = targets?.first?["skippedTags"]?.dictionaryValue
        let tags = skipped?["tags"]?.stringArrayValue
        #expect(tags == [".api"])
        #expect(skipped?["mode"]?.stringValue == "or")
    }

    @Test
    func `Adding to existing per-target block preserves mode`() throws {
        var plan = basePlan()
        var targets = try #require(plan["testTargets"]?.dictionaryArrayValue)
        var entry = targets[0]
        entry["skippedTags"] = ["mode": "or", "tags": [".api"]]
        targets[0] = entry
        plan["testTargets"] = .dictionaries(targets)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".cloudKit")]),
            "target_name": .string("AppTests"),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let resultTargets = json["testTargets"]?.dictionaryArrayValue
        let skipped = resultTargets?.first?["skippedTags"]?.dictionaryValue
        #expect(skipped?["tags"]?.stringArrayValue == [".api", ".cloudKit"])
        #expect(skipped?["mode"]?.stringValue == "or")
    }

    @Test
    func `Remove tags from plan-level defaults`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTags"] = ["mode": "or", "tags": [".api", ".testSuiteFile", ".slow"]]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".testSuiteFile")]),
            "action": .string("remove"),
        ]
        let result = try tool.execute(arguments: args)

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Removed"))

        let json = try TestPlanFile.read(from: path)
        let skipped = (json["defaultOptions"]?.dictionaryValue)?["skippedTags"]?.dictionaryValue
        let tags = skipped?["tags"]?.stringArrayValue
        #expect(tags == [".slow"])
    }

    @Test
    func `Remove all tags clears skippedTags key`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTags"] = ["mode": "or", "tags": [".api"]]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "action": .string("remove"),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let skipped = (json["defaultOptions"]?.dictionaryValue)?["skippedTags"]
        #expect(skipped == nil)
    }

    @Test
    func `Add duplicate tags is idempotent`() throws {
        var plan = basePlan()
        var defaults = try #require(plan["defaultOptions"]?.dictionaryValue)
        defaults["skippedTags"] = ["mode": "or", "tags": [".api"]]
        plan["defaultOptions"] = .dictionary(defaults)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api"), .string(".slow")]),
        ]
        _ = try tool.execute(arguments: args)

        let json = try TestPlanFile.read(from: path)
        let tags = json["defaultOptions"]?.dictionaryValue?["skippedTags"]?
            .dictionaryValue?["tags"]?.stringArrayValue
        #expect(tags == [".api", ".slow"])
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = [
            "test_plan_path": .string(path),
            "tags": .array([.string(".api")]),
            "target_name": .string("NonExistent"),
        ]
        #expect(throws: MCPError.self) { try tool.execute(arguments: args) }
    }

    @Test
    func `Empty tags array throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanSkippedTagsTool(pathUtility: pathUtility)
        let args: [String: Value] = ["test_plan_path": .string(path), "tags": .array([])]
        #expect(throws: MCPError.self) { try tool.execute(arguments: args) }
    }
}
