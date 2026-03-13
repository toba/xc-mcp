import MCP
import XCMCPCore
import CryptoKit
import Foundation

public struct SetPerformanceBaselineTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "set_performance_baseline",
            description:
            "Create or update Xcode performance baselines (.xcbaseline) for a test target. Extracts current averages from an xcresult bundle or accepts manual baseline values. Xcode uses these baselines for automatic regression detection.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj. Falls back to session default.",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the test target (e.g. 'DOMTests').",
                        ),
                    ]),
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to .xcresult bundle to extract current averages as baselines.",
                        ),
                    ]),
                    "baselines": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "test_name": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Full test identifier (e.g. 'DOMTests/testSorting()').",
                                    ),
                                ]),
                                "metric_identifier": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Metric identifier (e.g. 'com.apple.dt.XCTMetric_Clock.time.monotonic').",
                                    ),
                                ]),
                                "baseline_average": .object([
                                    "type": .string("number"),
                                    "description": .string(
                                        "The baseline average value.",
                                    ),
                                ]),
                                "max_percent_regression": .object([
                                    "type": .string("number"),
                                    "description": .string(
                                        "Maximum allowed regression percentage.",
                                    ),
                                ]),
                                "max_percent_relative_standard_deviation": .object([
                                    "type": .string("number"),
                                    "description": .string(
                                        "Maximum allowed relative standard deviation percentage.",
                                    ),
                                ]),
                            ]),
                            "required": .array([
                                .string("test_name"),
                                .string("metric_identifier"),
                                .string("baseline_average"),
                            ]),
                        ]),
                        "description": .string(
                            "Manual baseline entries. Alternative to result_bundle_path.",
                        ),
                    ]),
                ]),
                "required": .array([.string("target_name")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetName = try arguments.getRequiredString("target_name")
        let resultBundlePath = arguments.getString("result_bundle_path")

        // Resolve project path
        let projectPath: String
        if let path = arguments.getString("project_path") {
            projectPath = path
        } else {
            let (project, _) = try await sessionManager.resolveBuildPaths(from: arguments)
            guard let project else {
                throw MCPError.invalidParams(
                    "project_path is required (no session default set)",
                )
            }
            projectPath = project
        }

        guard FileManager.default.fileExists(atPath: projectPath) else {
            throw MCPError.invalidParams("Project not found at: \(projectPath)")
        }

        // Find target UUID from the pbxproj
        guard let targetUUID = PBXTargetMap.findUUID(
            projectPath: projectPath, targetName: targetName,
        ) else {
            throw MCPError.invalidParams("Target '\(targetName)' not found in project.")
        }

        // Collect baselines from xcresult or manual entries
        var baselineEntries: [BaselineEntry] = []

        if let resultBundlePath {
            guard FileManager.default.fileExists(atPath: resultBundlePath) else {
                throw MCPError.invalidParams(
                    "Result bundle not found at: \(resultBundlePath)",
                )
            }
            guard let metrics = await XCResultParser.parsePerformanceMetrics(
                at: resultBundlePath,
            ), !metrics.isEmpty else {
                throw MCPError.invalidParams(
                    "No performance metrics found in the result bundle.",
                )
            }
            baselineEntries = Self.entriesFromMetrics(metrics)
        }

        if case let .array(manualBaselines) = arguments["baselines"] {
            let manual = try Self.entriesFromManual(manualBaselines)
            baselineEntries.append(contentsOf: manual)
        }

        guard !baselineEntries.isEmpty else {
            throw MCPError.invalidParams(
                "Either result_bundle_path or baselines is required.",
            )
        }

        // Get machine metadata for Info.plist
        let machineInfo = MachineMetadata.current()
        let runDestUUID = Self.deterministicUUID(from: machineInfo)

        // Create xcbaseline directory
        let baselineDir =
            "\(projectPath)/xcshareddata/xcbaselines/\(targetUUID).xcbaseline"
        try FileManager.default.createDirectory(
            atPath: baselineDir,
            withIntermediateDirectories: true,
        )

        // Write/merge Info.plist
        try writeInfoPlist(
            at: "\(baselineDir)/Info.plist",
            runDestUUID: runDestUUID,
            machineInfo: machineInfo,
        )

        // Write/merge run-destination plist
        let count = try writeBaselinePlist(
            at: "\(baselineDir)/\(runDestUUID).plist",
            entries: baselineEntries,
        )

        return CallTool.Result(content: [.text(
            "Set \(count) performance baseline(s) for target '\(targetName)'.\nPath: \(baselineDir)",
        )])
    }

    // MARK: - Baseline Entry Extraction

    struct BaselineEntry {
        let className: String
        let methodName: String
        let metricIdentifier: String
        let baselineAverage: Double
        let maxPercentRegression: Double?
        let maxPercentRelativeStandardDeviation: Double?
    }

    static func entriesFromMetrics(
        _ metrics: [XCResultParser.PerformanceMetricResult],
    ) -> [BaselineEntry] {
        var entries: [BaselineEntry] = []
        for result in metrics {
            let parts = result.testIdentifier.split(separator: "/")
            let className: String
            let methodName: String
            if parts.count >= 2 {
                className = String(parts[parts.count - 2])
                methodName = String(parts[parts.count - 1])
            } else {
                className = result.testIdentifier
                methodName = result.testIdentifier
            }

            for run in result.testRuns {
                for metric in run.metrics {
                    guard !metric.measurements.isEmpty else { continue }
                    let avg = metric.measurements.reduce(0, +)
                        / Double(metric.measurements.count)
                    entries.append(BaselineEntry(
                        className: className,
                        methodName: methodName,
                        metricIdentifier: metric.identifier
                            ?? "com.apple.dt.XCTMetric_Clock.time.monotonic",
                        baselineAverage: avg,
                        maxPercentRegression: metric.maxPercentRegression,
                        maxPercentRelativeStandardDeviation: metric
                            .maxPercentRelativeStandardDeviation,
                    ))
                }
            }
        }
        return entries
    }

    static func entriesFromManual(_ array: [Value]) throws -> [BaselineEntry] {
        var entries: [BaselineEntry] = []
        for item in array {
            guard case let .object(obj) = item,
                  case let .string(testName) = obj["test_name"],
                  case let .string(metricId) = obj["metric_identifier"]
            else {
                throw MCPError.invalidParams(
                    "Each baseline entry must have test_name and metric_identifier.",
                )
            }

            let baselineAvg: Double
            if case let .double(v) = obj["baseline_average"] {
                baselineAvg = v
            } else if case let .int(v) = obj["baseline_average"] {
                baselineAvg = Double(v)
            } else {
                throw MCPError.invalidParams(
                    "baseline_average is required for each baseline entry.",
                )
            }

            let parts = testName.split(separator: "/")
            let className: String
            let methodName: String
            if parts.count >= 2 {
                className = String(parts[parts.count - 2])
                methodName = String(parts[parts.count - 1])
            } else {
                className = testName
                methodName = testName
            }

            var maxPctReg: Double?
            if case let .double(v) = obj["max_percent_regression"] { maxPctReg = v }
            var maxPctRSD: Double?
            if case let .double(v) = obj["max_percent_relative_standard_deviation"] {
                maxPctRSD = v
            }

            entries.append(BaselineEntry(
                className: className,
                methodName: methodName,
                metricIdentifier: metricId,
                baselineAverage: baselineAvg,
                maxPercentRegression: maxPctReg,
                maxPercentRelativeStandardDeviation: maxPctRSD,
            ))
        }
        return entries
    }

    // MARK: - UUID Generation

    static func deterministicUUID(from info: MachineMetadata.Info) -> String {
        let input = "\(info.modelCode)-\(info.cpuBrandString)-\(info.coreCount)-\(info.ramMegabytes)"
        let hash = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(hash)
        // Format first 16 bytes as UUID
        return String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        )
    }

    // MARK: - Plist Writing

    private func writeInfoPlist(
        at path: String,
        runDestUUID: String,
        machineInfo: MachineMetadata.Info,
    ) throws(MCPError) {
        var infoPlist: [String: Any]
        if let existing = NSDictionary(contentsOfFile: path) as? [String: Any] {
            infoPlist = existing
        } else {
            infoPlist = [:]
        }

        // Add/update run destination entry
        let destEntry: [String: Any] = [
            "cpuKind": machineInfo.cpuBrandString,
            "cpuCount": machineInfo.coreCount,
            "cpuSpeedInMHz": 0,
            "modelCode": machineInfo.modelCode,
            "physicalRAMAmountInMegabytes": machineInfo.ramMegabytes,
        ]
        infoPlist[runDestUUID] = destEntry

        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(
                fromPropertyList: infoPlist,
                format: .xml,
                options: 0,
            )
        } catch {
            throw .internalError("Failed to serialize Info.plist: \(error)")
        }

        do {
            try plistData.write(to: URL(fileURLWithPath: path))
        } catch {
            throw .internalError("Failed to write Info.plist: \(error)")
        }
    }

    private func writeBaselinePlist(
        at path: String,
        entries: [BaselineEntry],
    ) throws(MCPError) -> Int {
        // Load existing plist or start fresh
        // Structure: { "classNames": { "<class>": { "<method>": { "<metric>": { "baselineAverage": N } } } } }
        var plist: [String: Any]
        if let existing = NSDictionary(contentsOfFile: path) as? [String: Any] {
            plist = existing
        } else {
            plist = [:]
        }

        var classNames = plist["classNames"] as? [String: Any] ?? [:]

        for entry in entries {
            var classDict = classNames[entry.className] as? [String: Any] ?? [:]
            var methodDict = classDict[entry.methodName] as? [String: Any] ?? [:]

            var metricDict: [String: Any] = [
                "baselineAverage": entry.baselineAverage,
            ]
            if let maxReg = entry.maxPercentRegression {
                metricDict["maxPercentRegression"] = maxReg
            }
            if let maxRSD = entry.maxPercentRelativeStandardDeviation {
                metricDict["maxPercentRelativeStandardDeviation"] = maxRSD
            }

            methodDict[entry.metricIdentifier] = metricDict
            classDict[entry.methodName] = methodDict
            classNames[entry.className] = classDict
        }

        plist["classNames"] = classNames

        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0,
            )
        } catch {
            throw .internalError("Failed to serialize baseline plist: \(error)")
        }

        do {
            try plistData.write(to: URL(fileURLWithPath: path))
        } catch {
            throw .internalError("Failed to write baseline plist: \(error)")
        }

        return entries.count
    }
}
