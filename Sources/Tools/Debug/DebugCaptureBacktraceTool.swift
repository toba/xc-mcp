import MCP
import XCMCPCore
import Foundation

/// Sets a non-interactive, auto-continuing breakpoint that captures backtraces and resumes the
/// target on its own — the safe alternative to hand-rolling a conditional breakpoint on a hot
/// symbol (the footgun behind issue dq5-oel).
public struct DebugCaptureBacktraceTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = .init()) { self.lldbRunner = lldbRunner }

    public func tool() -> Tool {
        .init(
            name: "debug_capture_backtrace",
            description:
                "Capture the call stack when a function is hit, without leaving the process stopped. Sets an auto-continuing breakpoint that prints a backtrace and resumes, collects up to max_hits stacks, then stops. Bounded by a timeout and output cap so it cannot wedge the session — use this instead of a manual conditional breakpoint + debug_stack on high-frequency symbols.",
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
                    "symbol": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Function or method name to break on (e.g. 'sqlite3_prepare_v2').",
                        ),
                    ]),
                    "condition": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional LLDB breakpoint condition. Prefer register/memory comparisons over inferior function calls (strncmp/strstr), which are evaluated on every hit and slow the target dramatically.",
                        ),
                    ]),
                    "frame_count": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Max frames per backtrace. Omit for the full stack.",
                        ),
                    ]),
                    "max_hits": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of backtraces to capture before stopping (default 1).",
                        ),
                    ]),
                    "timeout_seconds": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Overall capture budget in seconds (default 10).",
                        ),
                    ]),
                ]),
                "required": .array([.string("symbol")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetPID = try await arguments.resolveDebugPID()
        let symbol = try arguments.getRequiredString("symbol")
        let condition = arguments.getString("condition")
        let frameCount = arguments.getInt("frame_count")
        let maxHits = arguments.getInt("max_hits") ?? 1
        let timeoutSeconds = arguments.getDouble("timeout_seconds") ?? 10

        do {
            var message = ""

            // Surface the same advisories as debug_lldb_command so a hot symbol / inferior-calling
            // condition is flagged even though this tool already bounds the capture.
            var probe = "breakpoint set --name \(symbol)"
            if let condition { probe += " --condition '\(condition)'" }
            let warnings = BreakpointConditionAdvisor.warnings(for: probe)
            if !warnings.isEmpty { message += warnings.joined(separator: "\n") + "\n\n" }

            let result = try await lldbRunner.captureBacktrace(
                pid: targetPID,
                symbol: symbol,
                condition: condition,
                frameCount: frameCount,
                maxHits: maxHits,
                timeoutSeconds: timeoutSeconds,
            )
            message += result.output

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }
}
