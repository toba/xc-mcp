import MCP
import XCMCPCore
import Foundation

public struct DebugEvaluateTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_evaluate",
            description:
            "Evaluate an expression in the context of a debugged process. Wraps po, p, and expr commands.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "expression": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Expression to evaluate.",
                        ),
                    ]),
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
                    "language": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Language for expression evaluation: 'swift' or 'objc'. Omit for auto-detection.",
                        ),
                    ]),
                    "object_description": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Use 'po' (print object description) instead of 'p'. Defaults to true.",
                        ),
                    ]),
                    "thread": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Thread index to select before evaluating. Use the thread that hit the breakpoint so 'self' and locals resolve.",
                        ),
                    ]),
                    "frame": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Stack frame index to select before evaluating (0 is the innermost frame).",
                        ),
                    ]),
                ]),
                "required": .array([.string("expression")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }

        let expression = try arguments.getRequiredString("expression")
        let language = arguments.getString("language")
        let objectDescription = arguments.getBool("object_description", default: true)
        let thread = arguments.getInt("thread")
        let frame = arguments.getInt("frame")

        do {
            // Warn if process is crashed — expression eval often fails in this state
            if let warning = await lldbRunner.crashWarning(pid: targetPID) {
                return CallTool.Result(
                    content: [.text(text: warning, annotations: nil, _meta: nil)],
                    isError: true,
                )
            }

            let result = try await lldbRunner.evaluate(
                pid: targetPID,
                expression: expression,
                language: language,
                objectDescription: objectDescription,
                thread: thread,
                frame: frame,
            )

            let message = "Expression result:\n\n\(result.output)"
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Wraps `execute` with a periodic heartbeat progress notification so the MCP client
    /// doesn't tool-call-timeout (and cancel) on Swift expressions whose JIT compile +
    /// inferior call exceed its default per-call patience — multi-line bodies that
    /// define a nested type then mutate AppKit/Foundation state are the slow path.
    public func executeWithProgress(
        arguments: [String: Value],
        progressToken: ProgressToken,
        notify: @escaping @Sendable (Message<ProgressNotification>) async throws -> Void,
    ) async throws -> CallTool.Result {
        let reporter = ProgressReporter(token: progressToken, notify: notify)
        return try await reporter.stream {
            let heartbeat = Task { [reporter] in
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { break }
                    let elapsed = Int((ContinuousClock.now - start).components.seconds)
                    reporter.ingest("evaluating expression… (\(elapsed)s)")
                }
            }
            defer { heartbeat.cancel() }
            return try await self.execute(arguments: arguments)
        }
    }
}
