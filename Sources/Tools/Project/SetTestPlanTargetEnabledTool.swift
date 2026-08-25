import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanTargetEnabledTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_test_plan_target_enabled",
            description:
                "Enable or disable a test target in a .xctestplan file without removing it",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the test target to enable or disable"),
                    ]),
                    "enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("true to enable the target, false to disable it"),
                    ]),
                ]),
                "required": .array([
                    .string("test_plan_path"), .string("target_name"), .string("enabled"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let testPlanPath = arguments.getString("test_plan_path"),
              let targetName = arguments.getString("target_name"),
              let enabled = arguments.getOptionalBool("enabled")
        else {
            throw MCPError.invalidParams("test_plan_path, target_name, and enabled are required")
        }

        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            guard json["testTargets"] != nil else {
                return CallTool.Result.text("Test plan has no test targets")
            }

            var testTargets = TestPlanFile.testTargets(in: json)
            var found = false

            for i in testTargets.indices
                where TestPlanFile.entry(testTargets[i], names: targetName)
            {
                found = true

                if enabled {
                    // Absent "enabled" key means enabled in Xcode's format
                    testTargets[i].removeValue(forKey: "enabled")
                } else {
                    testTargets[i]["enabled"] = .boolean(false)
                }
            }

            if !found {
                return CallTool.Result.text("Target '\(targetName)' not found in test plan")
            }

            json["testTargets"] = .dictionaries(testTargets)
            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            let action = enabled ? "Enabled" : "Disabled"
            return CallTool.Result.text(
                "\(action) target '\(targetName)' in test plan at \(resolvedTestPlanPath)")
        } catch {
            throw try error.asMCPError()
        }
    }
}
