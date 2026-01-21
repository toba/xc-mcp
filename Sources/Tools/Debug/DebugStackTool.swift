import Foundation
import XCMCPCore
import MCP

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
        var pid: Int32?
        if case let .int(value) = arguments["pid"] {
            pid = Int32(value)
        }

        if pid == nil, case let .string(bundleId) = arguments["bundle_id"] {
            pid = await LLDBSessionManager.shared.getSession(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required"
            )
        }

        // Get optional thread index
        let threadIndex: Int?
        if case let .int(value) = arguments["thread"] {
            threadIndex = value
        } else {
            threadIndex = nil
        }

        do {
            let result = try await lldbRunner.getStack(pid: targetPID, threadIndex: threadIndex)

            var message = "Stack trace for process \(targetPID)"
            if let threadIndex {
                message += " (thread \(threadIndex))"
            }
            message += ":\n\n\(result.output)"

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to get stack trace: \(error.localizedDescription)")
        }
    }
}
