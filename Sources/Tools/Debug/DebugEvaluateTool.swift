import MCP
import XCMCPCore
import Foundation

public struct DebugEvaluateTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_evaluate",
            description:
            "Evaluate an expression in the context of a debugged process. Wraps po, p, and expr commands.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "expression": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Expression to evaluate.",
                        ),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Language for expression evaluation: 'swift' or 'objc'. Omit for auto-detection.",
                        ),
                    ]),
                    "object_description": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Use 'po' (print object description) instead of 'p'. Defaults to true.",
                        ),
                    ]),
                ]),
                "required": .array([.string("expression")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }

        let expression = try arguments.getRequiredString("expression")
        let language = arguments.getString("language")
        let objectDescription = arguments.getBool("object_description", default: true)

        do {
            // Warn if process is crashed — expression eval often fails in this state
            if let warning = await lldbRunner.crashWarning(pid: targetPID) {
                return CallTool.Result(content: [.text(warning)], isError: true)
            }

            let result = try await lldbRunner.evaluate(
                pid: targetPID,
                expression: expression,
                language: language,
                objectDescription: objectDescription,
            )

            let message = "Expression result:\n\n\(result.output)"
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
