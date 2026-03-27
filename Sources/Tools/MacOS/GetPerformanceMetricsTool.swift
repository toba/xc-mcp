import MCP
import XCMCPCore
import Foundation

public struct GetPerformanceMetricsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "get_performance_metrics",
            description:
            "Extract performance metrics from an .xcresult bundle. Shows measurements from measure(metrics:) blocks including averages, standard deviations, and baselines.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcresult bundle.",
                        ),
                    ]),
                    "test_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter to a specific test identifier (e.g. 'MyTests/testSorting()').",
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
        let testId = arguments.getString("test_id")

        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            throw MCPError.invalidParams(
                "Result bundle not found at: \(resultBundlePath)",
            )
        }

        guard let results = await XCResultParser.parsePerformanceMetrics(
            at: resultBundlePath, testId: testId,
        ), !results.isEmpty else {
            return CallTool.Result(content: [.text(
                "No performance metrics found in the result bundle. Ensure tests use measure(metrics:) blocks.",
            )])
        }

        let output = Self.formatMetrics(results)
        return CallTool.Result(content: [.text(output)])
    }

    static func formatMetrics(_ results: [XCResultParser.PerformanceMetricResult]) -> String {
        var lines: [String] = []
        lines.append("Performance Metrics")
        lines.append("===================")

        for result in results {
            lines.append("")
            lines.append(result.testIdentifier)

            for run in result.testRuns {
                for metric in run.metrics {
                    let measurements = metric.measurements
                    guard !measurements.isEmpty else { continue }

                    let avg = measurements.reduce(0, +) / Double(measurements.count)
                    let variance = measurements.reduce(0) { $0 + ($1 - avg) * ($1 - avg) }
                        / Double(measurements.count)
                    let stdDev = variance.squareRoot()

                    var line = String(
                        format: "  %@ (%@): avg %.4g, std dev %.4g",
                        metric.displayName,
                        metric.unitOfMeasurement,
                        avg,
                        stdDev,
                    )

                    if let baseline = metric.baselineAverage {
                        line += String(format: ", baseline %.4g", baseline)
                    }

                    line += " (\(measurements.count) iterations)"
                    lines.append(line)
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
