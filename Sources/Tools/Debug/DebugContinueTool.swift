import Foundation
import MCP
import XCMCPCore

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
                            "Process ID of the debugged process."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session)."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get PID
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required"
            )
        }

        do {
            let result = try await lldbRunner.continueExecution(pid: targetPID)

            var message = "Continuing execution of process \(targetPID)"
            if !result.output.isEmpty {
                message += "\n\n\(result.output)"
            }

            return CallTool.Result(content: [
                .text(message),
                NextStepHints.content(hints: [
                    NextStepHint(tool: "debug_stack", description: "View the call stack"),
                    NextStepHint(
                        tool: "screenshot", description: "Take a screenshot to see current state"),
                ]),
            ])
        } catch {
            throw error.asMCPError()
        }
    }
}
