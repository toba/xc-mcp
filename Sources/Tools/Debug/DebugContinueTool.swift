import MCP
import XCMCPCore
import Foundation

public struct DebugContinueTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_continue",
            description:
            "Continue execution of a debugged process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
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
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()

        do {
            let result = try await lldbRunner.continueExecution(pid: targetPID)

            var message = "Continuing execution of process \(targetPID)"
            if !result.output.isEmpty {
                message += "\n\n\(result.output)"
            }

            return CallTool.Result(content: [
                .text(message),
            ])
        } catch {
            throw error.asMCPError()
        }
    }
}
