import Foundation
import MCP
import XCMCPCore

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
                            "Process ID of the debugged process."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session)."),
                    ]),
                    "thread": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Thread index to get stack for. Omit to get all threads."),
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

        // Get optional thread index
        let threadIndex = arguments.getInt("thread")

        do {
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
