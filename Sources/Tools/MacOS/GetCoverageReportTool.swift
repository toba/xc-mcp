import MCP
import XCMCPCore
import Foundation

public struct GetCoverageReportTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "get_coverage_report",
            description:
            "Get a code coverage report from an .xcresult bundle. Shows per-target coverage breakdown sorted by coverage ascending (weakest first). Use after running tests with code coverage enabled.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcresult bundle.",
                        ),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter to a specific target (case-insensitive substring match).",
                        ),
                    ]),
                    "show_files": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Include per-file breakdown under each target. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("result_bundle_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let resultBundlePath = try arguments.getRequiredString("result_bundle_path")
        let targetFilter = arguments.getString("target")
        let showFiles = arguments.getBool("show_files")

        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            throw MCPError.invalidParams(
                "Result bundle not found at: \(resultBundlePath)",
            )
        }

        let parser = CoverageParser()
        guard
            let report = await parser.parseCoverageReport(
                xcresultPath: resultBundlePath,
                targetFilter: targetFilter,
            )
        else {
            return CallTool.Result(content: [
                .text(
                    "No coverage data found in the result bundle. Ensure tests were run with code coverage enabled.",
                ),
            ])
        }

        let output = Self.formatReport(report, showFiles: showFiles)
        return CallTool.Result(content: [.text(output)])
    }

    static func formatReport(_ report: CoverageReport, showFiles: Bool) -> String {
        var lines: [String] = []
        lines.append("Code Coverage Report")
        lines.append("====================")
        lines.append(
            String(
                format: "Overall: %.1f%% (%d/%d lines)",
                report.lineCoverage,
                report.coveredLines,
                report.executableLines,
            ),
        )
        lines.append("")

        // Sort targets by coverage ascending (weakest first)
        let sorted = report.targets.sorted { $0.lineCoverage < $1.lineCoverage }

        lines.append("Targets:")
        for target in sorted {
            lines.append(
                String(
                    format: "  %@: %.1f%% (%d/%d lines)",
                    target.name,
                    target.lineCoverage,
                    target.coveredLines,
                    target.executableLines,
                ),
            )

            if showFiles {
                let sortedFiles = target.files.sorted { $0.lineCoverage < $1.lineCoverage }
                for file in sortedFiles {
                    lines.append(
                        String(
                            format: "    %@: %.1f%% (%d/%d)",
                            file.name,
                            file.lineCoverage,
                            file.coveredLines,
                            file.executableLines,
                        ),
                    )
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
