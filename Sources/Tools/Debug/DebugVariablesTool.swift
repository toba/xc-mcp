import Foundation
import MCP
import XCMCPCore

public struct DebugVariablesTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_variables",
            description:
                "Get local variables in the current stack frame of a debugged process.",
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
                    "frame": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Stack frame index. Defaults to 0 (current frame)."),
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

        // Get optional frame index
        let frameIndex: Int
        if case let .int(value) = arguments["frame"] {
            frameIndex = value
        } else {
            frameIndex = 0
        }

        do {
            let result = try await lldbRunner.getVariables(pid: targetPID, frameIndex: frameIndex)

            var message = "Variables in frame \(frameIndex) for process \(targetPID):\n\n"
            message += result.output

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
