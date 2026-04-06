import MCP
import XCMCPCore
import Foundation

/// Tracks allocation history for a specific memory address using `malloc_history`.
///
/// Wraps `/usr/bin/malloc_history` to show the allocation backtrace for a given
/// address. Requires the target process to have been launched with `MallocStackLogging=1`.
///
/// ## Example
///
/// ```
/// memory_malloc_history(pid: 12345, address: "0x600003c70000")
/// ```
public struct MemoryMallocHistoryTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "memory_malloc_history",
            description:
            "Show allocation backtrace for a specific memory address. Requires the process to have been launched with MallocStackLogging=1 environment variable. Use after finding a suspicious allocation via memory_heap or memory_leaks.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the target process.",
                        ),
                    ]),
                    "address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Memory address to look up (e.g., '0x600003c70000').",
                        ),
                    ]),
                    "full_stacks": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Show full stack traces instead of compact. Default: false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("address")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = try await arguments.resolveTargetPID()
        let address = try arguments.getRequiredString("address")
        let fullStacks = arguments.getBool("full_stacks")

        var args = ["\(pid)"]
        if fullStacks {
            args.append("-fullStacks")
        }
        args.append(address)

        let result = try await ProcessResult.run(
            "/usr/bin/malloc_history",
            arguments: args,
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            let hint =
                result.errorOutput.contains("stack logging")
                    ? " Hint: The target process must be launched with MallocStackLogging=1 environment variable."
                    : ""
            throw MCPError.internalError(
                "malloc_history failed (exit \(result.exitCode)): \(result.errorOutput)\(hint)",
            )
        }

        return CallTool.Result(content: [.text(
            text: result.stdout,
            annotations: nil,
            _meta: nil,
        )])
    }
}
