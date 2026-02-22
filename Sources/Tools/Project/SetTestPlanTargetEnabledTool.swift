import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanTargetEnabledTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
                        "description": .string(
                            "true to enable the target, false to disable it",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("test_plan_path"), .string("target_name"), .string("enabled"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(testPlanPath) = arguments["test_plan_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .bool(enabled) = arguments["enabled"]
        else {
            throw MCPError.invalidParams("test_plan_path, target_name, and enabled are required")
        }

        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            guard var testTargets = json["testTargets"] as? [[String: Any]] else {
                return CallTool.Result(
                    content: [.text("Test plan has no test targets")],
                )
            }

            var found = false
            for i in testTargets.indices {
                guard let target = testTargets[i]["target"] as? [String: Any],
                      let name = target["name"] as? String,
                      name == targetName
                else {
                    continue
                }
                found = true
                if enabled {
                    // Absent "enabled" key means enabled in Xcode's format
                    testTargets[i].removeValue(forKey: "enabled")
                } else {
                    testTargets[i]["enabled"] = false
                }
            }

            if !found {
                return CallTool.Result(
                    content: [
                        .text("Target '\(targetName)' not found in test plan"),
                    ],
                )
            }

            json["testTargets"] = testTargets
            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            let action = enabled ? "Enabled" : "Disabled"
            return CallTool.Result(
                content: [
                    .text(
                        "\(action) target '\(targetName)' in test plan at \(resolvedTestPlanPath)",
                    ),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to update test plan target: \(error.localizedDescription)",
            )
        }
    }
}
