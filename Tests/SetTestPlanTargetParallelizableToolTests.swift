import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SetTestPlanTargetParallelizableToolTests {
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
        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        #expect(tool.tool().name == "set_test_plan_target_parallelizable")
    }

    @Test
    func `Disable parallelization on specific target`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "target_name": .string("AppTests"),
            "enabled": .bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Disabled"))
        #expect(message.contains("target 'AppTests'"))

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue
        #expect(targets?.first?["parallelizable"]?.boolValue == false)
    }

    @Test
    func `Enable parallelization on specific target`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "target_name": .string("AppTests"),
            "enabled": .bool(true),
        ])

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"]?.dictionaryArrayValue
        #expect(targets?.first?["parallelizable"]?.boolValue == true)
    }

    @Test
    func `Overwrites existing parallelizable value`() throws {
        var plan = basePlan()
        var targets = try #require(plan["testTargets"]?.dictionaryArrayValue)
        targets[0]["parallelizable"] = true
        plan["testTargets"] = .dictionaries(targets)

        let path = try createTestPlan(plan)

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "target_name": .string("AppTests"),
            "enabled": .bool(false),
        ])

        let json = try TestPlanFile.read(from: path)
        let result = json["testTargets"]?.dictionaryArrayValue
        #expect(result?.first?["parallelizable"]?.boolValue == false)
    }

    @Test
    func `Plan-level default when target_name omitted`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "enabled": .bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("plan-level defaults"))

        let json = try TestPlanFile.read(from: path)
        let defaults = json["defaultOptions"]?.dictionaryValue
        #expect(defaults?["parallelizable"]?.boolValue == false)
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
                "target_name": .string("NonExistent"),
                "enabled": .bool(false),
            ])
        }
    }

    @Test
    func `Missing enabled throws error`() throws {
        let path = try createTestPlan(basePlan())

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: ["test_plan_path": .string(path)])
        }
    }
}
