import MCP
import XCMCPCore
import Foundation

/// Detects memory leaks in a running process using the `leaks` command.
///
/// Wraps `/usr/bin/leaks` and parses the output into a structured summary
/// showing leaked object counts, sizes, and backtraces.
///
/// ## Example
///
/// ```
/// memory_leaks(pid: 12345)
/// memory_leaks(bundle_id: "com.example.MyApp")
/// ```
public struct MemoryLeaksTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "memory_leaks",
            description:
            "Detect memory leaks in a running macOS process. Returns leaked object counts, sizes, and backtraces. Use pid or bundle_id to identify the target process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to check for leaks. Use this or bundle_id.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (e.g., 'com.example.MyApp'). Resolved to PID internally.",
                        ),
                    ]),
                    "group_by_backtrace": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Group leaks by allocation backtrace. Default: true.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = try await arguments.resolveTargetPID()
        let groupByBacktrace = arguments.getBool("group_by_backtrace", default: true)

        var args = ["\(pid)"]
        if groupByBacktrace {
            args.append("--groupByBacktrace")
        }

        let result = try await ProcessResult.run(
            "/usr/bin/leaks",
            arguments: args,
            timeout: .seconds(120),
        )

        // leaks returns exit code 1 when leaks are found — that's not an error
        if result.exitCode != 0, result.exitCode != 1 {
            throw MCPError.internalError(
                "leaks failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        let output = result.stdout.isEmpty ? result.output : result.stdout
        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }
}
