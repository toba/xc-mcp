import Foundation
import MCP
import XCMCPCore

public struct DebugWatchpointTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_watchpoint",
            description:
                "Manage watchpoints (data breakpoints) on a debugged process. Add, remove, or list watchpoints.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process."
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session)."
                        ),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Action to perform: 'add', 'remove', or 'list'."
                        ),
                    ]),
                    "variable": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Variable name to watch (for add action)."
                        ),
                    ]),
                    "address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Memory address in hex to watch (for add action, alternative to variable)."
                        ),
                    ]),
                    "watchpoint_id": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Watchpoint ID to remove (for remove action)."
                        ),
                    ]),
                    "condition": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Condition expression for the watchpoint (for add action)."
                        ),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required"
            )
        }

        let action = try arguments.getRequiredString("action")
        let variable = arguments.getString("variable")
        let address = arguments.getString("address")
        let watchpointId = arguments.getInt("watchpoint_id")
        let condition = arguments.getString("condition")

        do {
            let result = try await lldbRunner.manageWatchpoint(
                pid: targetPID,
                action: action,
                variable: variable,
                address: address,
                watchpointId: watchpointId,
                condition: condition
            )

            var message: String
            switch action {
            case "add":
                message = "Watchpoint added:\n\n\(result.output)"
            case "remove":
                message = "Watchpoint removed:\n\n\(result.output)"
            case "list":
                message = "Watchpoints:\n\n\(result.output)"
            default:
                message = result.output
            }

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
