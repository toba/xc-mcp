import MCP
import XCMCPCore
import Foundation

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
                            "Process ID of the debugged process.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                    "frame": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Stack frame index. Defaults to 0 (current frame).",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()

        // Get optional frame index
        let frameIndex = arguments.getInt("frame") ?? 0

        do {
            try await lldbRunner.requireStopped(pid: targetPID)
            let result = try await lldbRunner.getVariables(pid: targetPID, frameIndex: frameIndex)

            var message = "Variables in frame \(frameIndex) for process \(targetPID):\n\n"
            message += result.output

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
