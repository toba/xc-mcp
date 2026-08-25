import MCP
import XCMCPCore
import Foundation

public struct ShowPerformanceBaselinesTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) { self.sessionManager = sessionManager }

    public func tool() -> Tool {
        .init(
            name: "show_performance_baselines",
            description:
                "Display existing Xcode performance baselines (.xcbaseline) for test targets. Shows baseline averages, regression thresholds, and machine metadata in a readable format.",
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
                            "Filter to a specific test target name. If omitted, shows all targets with baselines.",
                        ),
                    ]),
                    "test_class": .object([
                        "type": .string("string"),
                        "description": .string("Filter to a specific test class name."),
                    ]),
                    "metric_filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter to metrics containing this string (e.g. 'clock', 'memory').",
                        ),
                    ]),
                ]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetNameFilter = arguments.getString("target_name")
        let testClassFilter = arguments.getString("test_class")
        let metricFilter = arguments.getString("metric_filter")

        // Resolve project path
        let projectPath: String

        if let path = arguments.getString("project_path") {
            projectPath = path
        } else {
            let (project, _) = try await sessionManager.resolveBuildPaths(from: arguments)
            guard let project else {
                throw MCPError.invalidParams("project_path is required (no session default set)")
            }
            projectPath = project
        }

        guard FileManager.default.fileExists(atPath: projectPath) else {
            throw MCPError.invalidParams("Project not found at: \(projectPath)")
        }

        // Scan for xcbaseline directories
        let baselinesDir = "\(projectPath)/xcshareddata/xcbaselines"
        let fm = FileManager.default

        guard fm.fileExists(atPath: baselinesDir) else {
            return CallTool.Result.text(
                "No performance baselines found. The directory does not exist:\n\(baselinesDir)")
        }

        let contents = (try? fm.contentsOfDirectory(atPath: baselinesDir)) ?? []
        let baselineDirs = contents.filter { $0.hasSuffix(".xcbaseline") }

        guard !baselineDirs.isEmpty else {
            return CallTool.Result.text("No .xcbaseline directories found in:\n\(baselinesDir)")
        }

        // Build target UUID → name map from pbxproj
        let targetMap = PBXTargetMap.buildMap(projectPath: projectPath)

        var output: [String] = []

        for baselineDir in baselineDirs.sorted() {
            let targetUUID = String(baselineDir.dropLast(".xcbaseline".count))
            let targetName = targetMap[targetUUID] ?? targetUUID

            // Apply target filter
            if let filter = targetNameFilter, targetName != filter { continue }

            let fullPath = "\(baselinesDir)/\(baselineDir)"

            // Read Info.plist for machine metadata
            let machineEntries = BaselineInfoPlist.read(from: "\(fullPath)/Info.plist")
                .machineSummaries

            // Find run-destination plists (UUID.plist files, not Info.plist)
            let plistFiles = ((try? fm.contentsOfDirectory(atPath: fullPath)) ?? [])
                .filter { $0.hasSuffix(".plist") && $0 != "Info.plist" }

            guard !plistFiles.isEmpty else { continue }

            for plistFile in plistFiles.sorted() {
                let runDestUUID = String(plistFile.dropLast(".plist".count))
                let machineDesc = machineEntries[runDestUUID]

                // Header
                var header = "\(targetName) Baselines"
                if let desc = machineDesc { header += " (\(desc))" }
                output.append(header)
                output.append(String(repeating: "=", count: header.count))

                // Parse baseline data
                let plistPath = "\(fullPath)/\(plistFile)"
                guard let data = fm.contents(atPath: plistPath),
                      let plist = try? PropertyListDecoder().decode(
                          PerformanceBaselinePlist.self, from: data,
                      )
                else {
                    output.append("  (unable to parse baseline data)")
                    output.append("")
                    continue
                }

                for className in plist.classNames.keys.sorted() {
                    // Apply test class filter
                    if let filter = testClassFilter,
                       !className.localizedCaseInsensitiveContains(filter) { continue }

                    guard let methods = plist.classNames[className] else { continue }

                    output.append(className)

                    for methodName in methods.keys.sorted() {
                        guard let metrics = methods[methodName] else { continue }

                        output.append("  \(methodName)")

                        for metricID in metrics.keys.sorted() {
                            // Apply metric filter
                            if let filter = metricFilter,
                               !metricID.localizedCaseInsensitiveContains(filter),
                               !Self.humanMetricName(metricID)
                                   .localizedCaseInsensitiveContains(filter) { continue }

                            guard let metric = metrics[metricID] else { continue }

                            var line = "    \(Self.humanMetricName(metricID)):"
                            if let avg = metric.baselineAverage {
                                line += "  \(Self.formatValue(avg, metricID: metricID))"
                            }
                            if let maxReg = metric.maxPercentRegression {
                                line += "  (max regression: \(Self.formatPercent(maxReg)))"
                            }
                            if let maxRSD = metric.maxPercentRelativeStandardDeviation {
                                line += "  (max stddev: \(Self.formatPercent(maxRSD)))"
                            }

                            output.append(line)
                        }
                    }
                }
                output.append("")
            }
        }

        return output.isEmpty
            ? CallTool.Result.text("No baselines match the specified filters.")
            : CallTool.Result.text(
                output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Formatting

    static let metricDisplayNames: [String: String] = [
        "com.apple.dt.XCTMetric_Clock.time.monotonic": "Clock Monotonic Time",
        "com.apple.dt.XCTMetric_Clock.time.wall": "Wall Clock Time",
        "com.apple.dt.XCTMetric_Memory.physical": "Memory Physical",
        "com.apple.dt.XCTMetric_Memory.physical_peak": "Memory Peak Physical",
        "com.apple.dt.XCTMetric_CPU.time": "CPU Time",
        "com.apple.dt.XCTMetric_CPU.instructions_retired": "CPU Instructions Retired",
        "com.apple.dt.XCTMetric_CPU.cycles": "CPU Cycles",
        "com.apple.dt.XCTMetric_Disk.logical_writes": "Disk Logical Writes",
        "com.apple.dt.XCTMetric_ApplicationLaunch.wallClockDuration.timeToFirstFrame":
            "App Launch (Time to First Frame)",
        "com.apple.dt.XCTMetric_ApplicationLaunch.wallClockDuration.timeToFirstFrameAfterResume":
            "App Launch (Resume to First Frame)",
        "com.apple.dt.XCTMetric_ApplicationLaunch.duration.appCreation":
            "App Launch (App Creation)",
        "com.apple.dt.XCTMetric_ApplicationLaunch.duration.firstFrameRendered":
            "App Launch (First Frame Rendered)",
    ]

    static func humanMetricName(_ identifier: String) -> String {
        metricDisplayNames[identifier] ?? identifier
    }

    static func formatValue(_ value: Double, metricID: String) -> String {
        if metricID.contains("Memory") || metricID.contains("memory") {
            if value >= 1_000_000 {
                return String(format: "%.1f GB", value / 1_000_000)
            } else if value >= 1000 {
                return String(format: "%.0f kB", value)
            } else {
                return String(format: "%.0f bytes", value)
            }
        }

        if metricID.contains("time") || metricID.contains("Clock")
            || metricID.contains("Duration") || metricID.contains("duration")
        {
            return value >= 1.0 ? String(format: "%.3fs", value) : String(format: "%.4fs", value)
        }

        // Generic numeric
        if value == value.rounded(), value < 1_000_000 { return String(format: "%.0f", value) }
        return .init(format: "%.4g", value)
    }

    static func formatPercent(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }
}
