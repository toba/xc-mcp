import MCP
import XCMCPCore
import Foundation

public struct DebugStackTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_stack",
            description:
            "Get the current call stack (backtrace) of a debugged process.",
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
                    "thread": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Thread index to get stack for. Omit to get all threads.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()

        // Get optional thread index
        let threadIndex = arguments.getInt("thread")

        do {
            try await lldbRunner.requireStopped(pid: targetPID)
            let result = try await lldbRunner.getStack(pid: targetPID, threadIndex: threadIndex)

            var message = "Stack trace for process \(targetPID)"
            if let threadIndex {
                message += " (thread \(threadIndex))"
            }
            message += ":\n\n\(result.output)"

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
