import Foundation
import MCP
import XCMCPCore

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
                            "Process ID of the debugged process."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session)."),
                    ]),
                    "command": .object([
                        "type": .string("string"),
                        "description": .string(
                            "LLDB command to execute (e.g., 'po self', 'expr myVar = 5')."),
                    ]),
                ]),
                "required": .array([.string("command")]),
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

        // Get command
        guard case let .string(command) = arguments["command"] else {
            throw MCPError.invalidParams("command is required")
        }

        do {
            let result = try await lldbRunner.executeCommand(pid: targetPID, command: command)

            var message = "LLDB command result:\n\n"
            message += result.output

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to execute LLDB command: \(error.localizedDescription)")
        }
    }
}
