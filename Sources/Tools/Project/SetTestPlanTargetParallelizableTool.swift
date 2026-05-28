import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanTargetParallelizableTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "set_test_plan_target_parallelizable",
            description:
            "Set the 'parallelizable' flag on a test plan target (or plan-level defaultOptions). Use enabled=false to opt a target out of Swift Testing's default parallel execution — needed when test code transitively triggers main-queue dispatch (CloudKit, CoreSymbolication, etc.) and trips libdispatch's main-thread assertion.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "enabled": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "true to mark as parallelizable, false to disable parallel execution",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of a specific test target. If omitted, applies to plan-level defaultOptions.",
                        ),
                    ]),
                ]),
                "required": .array([.string("test_plan_path"), .string("enabled")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let testPlanPath = try arguments.getRequiredString("test_plan_path")
        guard case let .bool(enabled) = arguments["enabled"] else {
            throw MCPError.invalidParams("enabled is required and must be a boolean")
        }
        let targetName = arguments.getString("target_name")

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            if let targetName {
                try applyToTarget(&json, targetName: targetName, enabled: enabled)
            } else {
                applyToDefaults(&json, enabled: enabled)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let verb = enabled ? "Enabled" : "Disabled"
            return CallTool.Result(
                content: [
                    .text(
                        text: "\(verb) parallel execution for \(scope) in \(resolvedPath)",
                        annotations: nil,
                        _meta: nil,
                    ),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to update test plan parallelizable setting: \(error.localizedDescription)",
            )
        }
    }

    private func applyToDefaults(_ json: inout [String: Any], enabled: Bool) {
        var defaults = json["defaultOptions"] as? [String: Any] ?? [:]
        defaults["parallelizable"] = enabled
        json["defaultOptions"] = defaults
    }

    private func applyToTarget(
        _ json: inout [String: Any],
        targetName: String,
        enabled: Bool,
    ) throws(MCPError) {
        guard var testTargets = json["testTargets"] as? [[String: Any]] else {
            throw MCPError.invalidParams("Test plan has no test targets")
        }

        guard
            let index = testTargets.firstIndex(where: {
                ($0["target"] as? [String: Any])?["name"] as? String == targetName
            })
        else {
            throw MCPError.invalidParams("Target '\(targetName)' not found in test plan")
        }

        var entry = testTargets[index]
        entry["parallelizable"] = enabled
        testTargets[index] = entry
        json["testTargets"] = testTargets
    }
}
