import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanTargetParallelizableTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
        guard let enabled = arguments.getOptionalBool("enabled") else {
            throw MCPError.invalidParams("enabled is required and must be a boolean")
        }
        let targetName = arguments.getString("target_name")

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            try TestPlanFile.mutateScope(&json, targetName: targetName) { scope in
                scope["parallelizable"] = .boolean(enabled)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let verb = enabled ? "Enabled" : "Disabled"
            return CallTool.Result.text(
                "\(verb) parallel execution for \(scope) in \(resolvedPath)")
        } catch {
            throw try error.asMCPError()
        }
    }
}
