import MCP
import XCMCPCore
import Foundation

/// Examines heap allocations in a running process using the `heap` command.
///
/// Wraps `/usr/bin/heap` to show all heap allocations organized by class,
/// sorted by size or count. Useful for identifying which objects consume the most memory.
///
/// ## Example
///
/// ```
/// memory_heap(pid: 12345, sort_by: "size")
/// memory_heap(bundle_id: "com.example.MyApp", top_n: 30)
/// ```
public struct MemoryHeapTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "memory_heap",
            description:
            "Examine heap allocations in a running macOS process. Shows all heap objects organized by class, sorted by total size or count. Use to find which objects consume the most memory.",
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
                    "sort_by": .object([
                        "type": .string("string"),
                        "enum": .array([.string("size"), .string("count")]),
                        "description": .string(
                            "Sort order: 'size' (default) sorts by total bytes, 'count' sorts by instance count.",
                        ),
                    ]),
                    "top_n": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Limit output to the top N classes. Default: all.",
                        ),
                    ]),
                    "class_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter to show only allocations of this class name.",
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
        let sortBy = arguments.getString("sort_by") ?? "size"

        var args: [String] = []
        if sortBy == "size" {
            args.append("--sortBySize")
        }
        args.append("\(pid)")

        let result = try await ProcessResult.run(
            "/usr/bin/heap",
            arguments: args,
            timeout: .seconds(60),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "heap failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        var output = result.stdout

        // Apply class name filter if specified
        if let className = arguments.getString("class_name") {
            let lines = output.components(separatedBy: "\n")
            let filtered = lines.filter { line in
                line.contains(className) || line.hasPrefix("Process") || line.hasPrefix("Zone")
                    || line.hasPrefix("All")
            }
            output = filtered.joined(separator: "\n")
        }

        // Apply top_n limit if specified
        if let topN = arguments.getInt("top_n") {
            let lines = output.components(separatedBy: "\n")
            // Keep header lines (non-data lines at the top) plus topN data lines
            var headerLines: [String] = []
            var dataLines: [String] = []
            var inData = false
            for line in lines {
                if !inData {
                    if line.contains("BYTES"), line.contains("COUNT") {
                        inData = true
                        headerLines.append(line)
                    } else {
                        headerLines.append(line)
                    }
                } else {
                    dataLines.append(line)
                }
            }
            let limited = headerLines + Array(dataLines.prefix(topN))
            output = limited.joined(separator: "\n")
        }

        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }
}
