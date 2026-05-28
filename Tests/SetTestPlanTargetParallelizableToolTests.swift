import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct SetTestPlanTargetParallelizableToolTests {
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
        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        #expect(tool.tool().name == "set_test_plan_target_parallelizable")
    }

    @Test
    func `Disable parallelization on specific target`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

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
        let targets = json["testTargets"] as? [[String: Any]]
        #expect(targets?.first?["parallelizable"] as? Bool == false)
    }

    @Test
    func `Enable parallelization on specific target`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "target_name": .string("AppTests"),
            "enabled": .bool(true),
        ])

        let json = try TestPlanFile.read(from: path)
        let targets = json["testTargets"] as? [[String: Any]]
        #expect(targets?.first?["parallelizable"] as? Bool == true)
    }

    @Test
    func `Overwrites existing parallelizable value`() throws {
        var plan = basePlan()
        var targets = try #require(plan["testTargets"] as? [[String: Any]])
        targets[0]["parallelizable"] = true
        plan["testTargets"] = targets

        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "target_name": .string("AppTests"),
            "enabled": .bool(false),
        ])

        let json = try TestPlanFile.read(from: path)
        let result = json["testTargets"] as? [[String: Any]]
        #expect(result?.first?["parallelizable"] as? Bool == false)
    }

    @Test
    func `Plan-level default when target_name omitted`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

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
        let defaults = json["defaultOptions"] as? [String: Any]
        #expect(defaults?["parallelizable"] as? Bool == false)
    }

    @Test
    func `Target not found throws error`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

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
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanTargetParallelizableTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
            ])
        }
    }
}
