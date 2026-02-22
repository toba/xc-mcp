import Foundation
import MCP
import XCMCPCore

public struct RemoveTargetFromTestPlanTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_target_from_test_plan",
            description: "Remove a test target from a .xctestplan file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the test target to remove"),
                    ]),
                ]),
                "required": .array([.string("test_plan_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(testPlanPath) = arguments["test_plan_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("test_plan_path and target_name are required")
        }

        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            guard var testTargets = json["testTargets"] as? [[String: Any]] else {
                return CallTool.Result(
                    content: [.text("Test plan has no test targets")]
                )
            }

            let originalCount = testTargets.count
            testTargets.removeAll { entry in
                guard let target = entry["target"] as? [String: Any],
                    let name = target["name"] as? String
                else {
                    return false
                }
                return name == targetName
            }

            if testTargets.count == originalCount {
                return CallTool.Result(
                    content: [
                        .text(
                            "Target '\(targetName)' not found in test plan"
                        )
                    ]
                )
            }

            json["testTargets"] = testTargets
            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            return CallTool.Result(
                content: [
                    .text(
                        "Removed target '\(targetName)' from test plan at \(resolvedTestPlanPath)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove target from test plan: \(error.localizedDescription)"
            )
        }
    }
}
