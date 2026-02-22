import MCP
import XCMCPCore
import Foundation

public struct DebugLLDBCommandTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_lldb_command",
            description:
            "Execute a custom LLDB command on a debugged process.",
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
                    "command": .object([
                        "type": .string("string"),
                        "description": .string(
                            "LLDB command to execute (e.g., 'po self', 'expr myVar = 5').",
                        ),
                    ]),
                ]),
                "required": .array([.string("command")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()

        // Get command
        let command = try arguments.getRequiredString("command")

        do {
            let result = try await lldbRunner.executeCommand(pid: targetPID, command: command)

            var message = "LLDB command result:\n\n"
            message += result.output

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
