import MCP
import XCMCPCore
import Foundation

/// Displays virtual memory mapping for a running process using `vmmap`.
///
/// Wraps `/usr/bin/vmmap` to show virtual memory regions including dirty,
/// clean, and swapped pages, organized by region type.
///
/// ## Example
///
/// ```
/// memory_vmmap(pid: 12345)
/// memory_vmmap(bundle_id: "com.example.MyApp", summary: true)
/// ```
public struct MemoryVmmapTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "memory_vmmap",
            description:
            "Display virtual memory mapping for a running macOS process. Shows memory regions with dirty/clean/swapped breakdown. Use summary mode for a concise overview, or full mode for per-region detail.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to examine. Use this or bundle_id.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (e.g., 'com.example.MyApp'). Resolved to PID internally.",
                        ),
                    ]),
                    "summary": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Show only the summary section (region types with totals). Default: true.",
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
        let summary = arguments.getBool("summary", default: true)

        var args: [String] = []
        if summary {
            args.append("-summary")
        }
        args.append("\(pid)")

        let result = try await ProcessResult.run(
            "/usr/bin/vmmap",
            arguments: args,
            timeout: .seconds(60),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "vmmap failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result(content: [.text(
            text: result.stdout,
            annotations: nil,
            _meta: nil,
        )])
    }
}
