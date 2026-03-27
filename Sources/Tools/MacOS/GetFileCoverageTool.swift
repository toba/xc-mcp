import MCP
import XCMCPCore
import Foundation

public struct GetFileCoverageTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "get_file_coverage",
            description:
            "Get function-level code coverage for a specific file from an .xcresult bundle. Shows each function's coverage and execution count. Optionally includes uncovered line ranges.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcresult bundle.",
                        ),
                    ]),
                    "file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Source file path to get coverage for.",
                        ),
                    ]),
                    "show_lines": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include uncovered line ranges. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("result_bundle_path"), .string("file")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let resultBundlePath = try arguments.getRequiredString("result_bundle_path")
        let filePath = try arguments.getRequiredString("file")
        let showLines = arguments.getBool("show_lines")

        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            throw MCPError.invalidParams(
                "Result bundle not found at: \(resultBundlePath)",
            )
        }

        let parser = CoverageParser()
        guard let fileCoverage = await parser.parseFunctionCoverage(
            xcresultPath: resultBundlePath,
            filePath: filePath,
        ) else {
            return CallTool.Result(content: [.text(
                "No coverage data found for file: \(filePath). Ensure the file is part of a target that was tested with coverage enabled.",
            )])
        }

        var output = Self.formatFileCoverage(fileCoverage)

        if showLines {
            if let uncoveredRanges = await parser.parseUncoveredLines(
                xcresultPath: resultBundlePath,
                filePath: filePath,
            ), !uncoveredRanges.isEmpty {
                output += "\n\n"
                output += Self.formatUncoveredRanges(uncoveredRanges)
            }
        }

        return CallTool.Result(content: [.text(output)])
    }

    static func formatFileCoverage(_ coverage: FileFunctionCoverage) -> String {
        var lines: [String] = []
        lines.append("File Coverage: \(coverage.path)")
        lines.append(String(
            format: "Coverage: %.1f%% (%d/%d lines)",
            coverage.lineCoverage,
            coverage.coveredLines,
            coverage.executableLines,
        ))
        lines.append("")

        // Sort: uncovered first, then by line number
        let sorted = coverage.functions.sorted { a, b in
            if a.executionCount == 0, b.executionCount != 0 { return true }
            if a.executionCount != 0, b.executionCount == 0 { return false }
            return a.lineNumber < b.lineNumber
        }

        lines.append("Functions:")
        for fn in sorted {
            let prefix = fn.executionCount == 0 ? "[NOT COVERED] " : ""
            lines.append(String(
                format: "  %@L%d %@: %.1f%% (%d/%d, called %dx)",
                prefix,
                fn.lineNumber,
                fn.name,
                fn.lineCoverage,
                fn.coveredLines,
                fn.executableLines,
                fn.executionCount,
            ))
        }

        return lines.joined(separator: "\n")
    }

    static func formatUncoveredRanges(_ ranges: [UncoveredRange]) -> String {
        var lines: [String] = []
        lines.append("Uncovered Lines:")
        for range in ranges {
            if range.start == range.end {
                lines.append("  L\(range.start)")
            } else {
                lines.append("  L\(range.start)-\(range.end)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
