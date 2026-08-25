import MCP
import XCMCPCore
import Foundation

public struct RemoveTargetFromTestPlanTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let testPlanPath = arguments.getString("test_plan_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("test_plan_path and target_name are required") }

        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            guard json["testTargets"] != nil else {
                return CallTool.Result.text("Test plan has no test targets")
            }

            var testTargets = TestPlanFile.testTargets(in: json)
            let originalCount = testTargets.count
            testTargets.removeAll { TestPlanFile.entry($0, names: targetName) }

            if testTargets.count == originalCount {
                return CallTool.Result.text("Target '\(targetName)' not found in test plan")
            }

            json["testTargets"] = .dictionaries(testTargets)
            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            return CallTool.Result.text(
                "Removed target '\(targetName)' from test plan at \(resolvedTestPlanPath)")
        } catch {
            throw try error.asMCPError()
        }
    }
}
