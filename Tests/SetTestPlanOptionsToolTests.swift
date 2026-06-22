import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct SetTestPlanOptionsToolTests {
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
        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        #expect(tool.tool().name == "set_test_plan_options")
    }

    @Test
    func `Set enum and bool options on plan-level defaults`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "diagnostic_collection_policy": .string("OnFailure"),
            "user_attachment_lifetime": .string("keepNever"),
            "code_coverage": .bool(true),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("plan-level defaultOptions"))

        let json = try TestPlanFile.read(from: path)
        let defaults = try #require(json["defaultOptions"] as? [String: Any])
        #expect(defaults["diagnosticCollectionPolicy"] as? String == "OnFailure")
        #expect(defaults["userAttachmentLifetime"] as? String == "keepNever")
        #expect(defaults["codeCoverage"] as? Bool == true)
    }

    @Test
    func `Set options on a named configuration`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "configuration_name": .string("Default"),
            "main_thread_checker_enabled": .bool(false),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("configuration 'Default'"))

        let json = try TestPlanFile.read(from: path)
        let configs = try #require(json["configurations"] as? [[String: Any]])
        let options = try #require(configs.first?["options"] as? [String: Any])
        #expect(options["mainThreadCheckerEnabled"] as? Bool == false)
        // defaultOptions untouched
        let defaults = json["defaultOptions"] as? [String: Any]
        #expect(defaults?["mainThreadCheckerEnabled"] == nil)
    }

    @Test
    func `Only provided keys are written, others untouched`() throws {
        var plan = basePlan()
        plan["defaultOptions"] = ["codeCoverage": true, "mainThreadCheckerEnabled": true]
        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "code_coverage": .bool(false),
        ])

        let json = try TestPlanFile.read(from: path)
        let defaults = try #require(json["defaultOptions"] as? [String: Any])
        #expect(defaults["codeCoverage"] as? Bool == false)
        // Untouched key preserved
        #expect(defaults["mainThreadCheckerEnabled"] as? Bool == true)
    }

    @Test
    func `Clear removes a key`() throws {
        var plan = basePlan()
        plan["defaultOptions"] = ["codeCoverage": true, "diagnosticCollectionPolicy": "Always"]
        let path = try createTestPlan(plan)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "test_plan_path": .string(path),
            "clear": .array([.string("code_coverage")]),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("cleared codeCoverage"))

        let json = try TestPlanFile.read(from: path)
        let defaults = try #require(json["defaultOptions"] as? [String: Any])
        #expect(defaults["codeCoverage"] == nil)
        #expect(defaults["diagnosticCollectionPolicy"] as? String == "Always")
    }

    @Test
    func `Invalid enum value throws`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
                "diagnostic_collection_policy": .string("Sometimes"),
            ])
        }
    }

    @Test
    func `Unknown clear key throws`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
                "clear": .array([.string("bogus_option")]),
            ])
        }
    }

    @Test
    func `No options provided throws`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
            ])
        }
    }

    @Test
    func `Unknown configuration throws`() throws {
        let path = try createTestPlan(basePlan())
        defer { try? FileManager.default.removeItem(atPath: path) }

        let tool = SetTestPlanOptionsTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "test_plan_path": .string(path),
                "configuration_name": .string("Nonexistent"),
                "code_coverage": .bool(true),
            ])
        }
    }
}
