import MCP
import XCMCPCore
import Foundation

/// Finds duplicate strings wasting memory in a running process using `stringdups`.
///
/// Wraps `/usr/bin/stringdups` to identify string objects that appear multiple
/// times in the heap, sorted by wasted bytes.
///
/// ## Example
///
/// ```
/// memory_stringdups(pid: 12345)
/// memory_stringdups(bundle_id: "com.example.MyApp", top_n: 50)
/// ```
public struct MemoryStringDupsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "memory_stringdups",
            description:
            "Find duplicate strings wasting memory in a running macOS process. Shows repeated string values with their copy count and total wasted bytes, sorted by wasted memory.",
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
                    "top_n": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of top duplicate strings to return. Default: 30.",
                        ),
                    ]),
                    "min_count": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Minimum duplicate count to report. Default: 2.",
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
        let topN = arguments.getInt("top_n") ?? 30
        let minCount = arguments.getInt("min_count") ?? 2

        let args = [
            "--minimumCount=\(minCount)",
            "--nostacks",
            "\(pid)",
        ]

        let result = try await ProcessResult.run(
            "/usr/bin/stringdups",
            arguments: args,
            timeout: .seconds(60),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "stringdups failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        // Limit output to top N entries
        var output = result.stdout
        let lines = output.components(separatedBy: "\n")
        // stringdups output has header lines followed by data
        var headerLines: [String] = []
        var dataLines: [String] = []
        var pastHeader = false
        for line in lines {
            if !pastHeader {
                headerLines.append(line)
                // Data lines typically start with a number or whitespace+number
                if line.trimmingCharacters(in: .whitespaces).first?.isNumber == true,
                   headerLines.count > 2
                {
                    pastHeader = true
                    headerLines.removeLast()
                    dataLines.append(line)
                }
            } else {
                dataLines.append(line)
            }
        }
        let limited = headerLines + Array(dataLines.prefix(topN))
        output = limited.joined(separator: "\n")

        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }
}
