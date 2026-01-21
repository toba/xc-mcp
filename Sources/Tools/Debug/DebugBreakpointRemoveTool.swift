import Foundation
import XCMCPCore
import MCP

public struct DebugBreakpointRemoveTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_breakpoint_remove",
            description:
                "Remove a breakpoint from a debugging session.",
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
                    "breakpoint_id": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "ID of the breakpoint to remove."),
                    ]),
                ]),
                "required": .array([.string("breakpoint_id")]),
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

        // Get breakpoint ID
        guard case let .int(breakpointId) = arguments["breakpoint_id"] else {
            throw MCPError.invalidParams("breakpoint_id is required")
        }

        do {
            let result = try await lldbRunner.deleteBreakpoint(
                pid: targetPID, breakpointId: breakpointId)

            var message = "Breakpoint \(breakpointId) removed"
            message += "\n\n\(result.output)"

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove breakpoint: \(error.localizedDescription)")
        }
    }
}
