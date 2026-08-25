import MCP
import XCMCPCore
import Foundation

public struct DebugStepTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = .init()) { self.lldbRunner = lldbRunner }

    public func tool() -> Tool {
        .init(
            name: "debug_step",
            description: "Step through code execution in a debugged process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string("Process ID of the debugged process."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                    "mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Step mode: 'in' (step into), 'over' (step over), 'out' (step out), or 'instruction' (single instruction).",
                        ),
                    ]),
                ]),
                "required": .array([.string("mode")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()

        let mode = try arguments.getRequiredString("mode")

        guard ["in", "over", "out", "instruction"].contains(mode) else {
            throw MCPError.invalidParams("mode must be 'in', 'over', 'out', or 'instruction'")
        }

        do {
            try await lldbRunner.requireStopped(pid: targetPID)
            let result = try await lldbRunner.step(pid: targetPID, mode: mode)

            let modeDesc: String

            switch mode {
                case "in": modeDesc = "Stepped into"
                case "over": modeDesc = "Stepped over"
                case "out": modeDesc = "Stepped out"
                case "instruction": modeDesc = "Stepped instruction"
                default: modeDesc = "Stepped"
            }

            let message = "\(modeDesc):\n\n\(result.output)"
            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
