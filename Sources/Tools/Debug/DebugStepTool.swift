import Foundation
import MCP
import XCMCPCore

public struct DebugStepTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_step",
            description:
                "Step through code execution in a debugged process.",
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
                    "mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Step mode: 'in' (step into), 'over' (step over), 'out' (step out), or 'instruction' (single instruction)."
                        ),
                    ]),
                ]),
                "required": .array([.string("mode")]),
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

        let mode = try arguments.getRequiredString("mode")

        guard ["in", "over", "out", "instruction"].contains(mode) else {
            throw MCPError.invalidParams(
                "mode must be 'in', 'over', 'out', or 'instruction'"
            )
        }

        do {
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
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
