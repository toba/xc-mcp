import MCP
import XCMCPCore
import Foundation

public struct ShowPerformanceBaselinesTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
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
                        "description": .string(
                            "Filter to a specific test class name.",
                        ),
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
                throw MCPError.invalidParams(
                    "project_path is required (no session default set)",
                )
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
            return CallTool.Result(content: [.text(
                "No performance baselines found. The directory does not exist:\n\(baselinesDir)",
            )])
        }

        let contents = (try? fm.contentsOfDirectory(atPath: baselinesDir)) ?? []
        let baselineDirs = contents.filter { $0.hasSuffix(".xcbaseline") }

        guard !baselineDirs.isEmpty else {
            return CallTool.Result(content: [.text(
                "No .xcbaseline directories found in:\n\(baselinesDir)",
            )])
        }

        // Build target UUID → name map from pbxproj
        let targetMap = PBXTargetMap.buildMap(projectPath: projectPath)

        var output: [String] = []

        for baselineDir in baselineDirs.sorted() {
            let targetUUID = String(baselineDir.dropLast(".xcbaseline".count))
            let targetName = targetMap[targetUUID] ?? targetUUID

            // Apply target filter
            if let filter = targetNameFilter, targetName != filter {
                continue
            }

            let fullPath = "\(baselinesDir)/\(baselineDir)"

            // Read Info.plist for machine metadata
            let infoPlistPath = "\(fullPath)/Info.plist"
            let machineEntries = parseMachineInfo(at: infoPlistPath)

            // Find run-destination plists (UUID.plist files, not Info.plist)
            let plistFiles = ((try? fm.contentsOfDirectory(atPath: fullPath)) ?? [])
                .filter { $0.hasSuffix(".plist") && $0 != "Info.plist" }

            guard !plistFiles.isEmpty else { continue }

            for plistFile in plistFiles.sorted() {
                let runDestUUID = String(plistFile.dropLast(".plist".count))
                let machineDesc = machineEntries[runDestUUID]

                // Header
                var header = "\(targetName) Baselines"
                if let desc = machineDesc {
                    header += " (\(desc))"
                }
                output.append(header)
                output.append(String(repeating: "=", count: header.count))

                // Parse baseline data
                let plistPath = "\(fullPath)/\(plistFile)"
                guard let data = fm.contents(atPath: plistPath),
                      let plist = try? PropertyListSerialization.propertyList(
                          from: data, format: nil,
                      ) as? [String: Any],
                      let classNames = plist["classNames"] as? [String: Any]
                else {
                    output.append("  (unable to parse baseline data)")
                    output.append("")
                    continue
                }

                let sortedClasses = classNames.keys.sorted()
                for className in sortedClasses {
                    // Apply test class filter
                    if let filter = testClassFilter,
                       !className.localizedCaseInsensitiveContains(filter)
                    {
                        continue
                    }

                    guard let methods = classNames[className] as? [String: Any] else { continue }

                    output.append(className)

                    let sortedMethods = methods.keys.sorted()
                    for methodName in sortedMethods {
                        guard let metrics = methods[methodName] as? [String: Any] else { continue }

                        output.append("  \(methodName)")

                        let sortedMetrics = metrics.keys.sorted()
                        for metricId in sortedMetrics {
                            // Apply metric filter
                            if let filter = metricFilter,
                               !metricId.localizedCaseInsensitiveContains(filter),
                               !Self.humanMetricName(metricId)
                               .localizedCaseInsensitiveContains(filter)
                            {
                                continue
                            }

                            guard let metricDict = metrics[metricId] as? [String: Any] else {
                                continue
                            }

                            let displayName = Self.humanMetricName(metricId)
                            let avg = metricDict["baselineAverage"] as? Double

                            var line = "    \(displayName):"
                            if let avg {
                                line += "  \(Self.formatValue(avg, metricId: metricId))"
                            }

                            if let maxReg = metricDict["maxPercentRegression"] as? Double {
                                line += "  (max regression: \(Self.formatPercent(maxReg)))"
                            }
                            if let maxRSD = metricDict[
                                "maxPercentRelativeStandardDeviation",
                            ] as? Double {
                                line += "  (max stddev: \(Self.formatPercent(maxRSD)))"
                            }

                            output.append(line)
                        }
                    }
                }
                output.append("")
            }
        }

        if output.isEmpty {
            return CallTool.Result(content: [.text(
                "No baselines match the specified filters.",
            )])
        }

        return CallTool.Result(content: [.text(
            output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
        )])
    }

    // MARK: - Machine Info Parsing

    private func parseMachineInfo(at path: String) -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(
                  from: data, format: nil,
              ) as? [String: Any]
        else {
            return [:]
        }

        var result = [String: String]()

        // Xcode format: { runDestinationsByUUID: { UUID: { localComputer: { cpuKind, modelCode, ... } } } }
        if let byUUID = dict["runDestinationsByUUID"] as? [String: Any] {
            for (uuid, value) in byUUID {
                guard let dest = value as? [String: Any],
                      let computer = dest["localComputer"] as? [String: Any]
                else { continue }
                let cpu = computer["cpuKind"] as? String ?? "Unknown CPU"
                let model = computer["modelCode"] as? String ?? "Unknown"
                result[uuid] = "\(cpu), \(model)"
            }
            return result
        }

        // Flat format from set_performance_baseline: { UUID: { cpuKind, modelCode, ... } }
        for (key, value) in dict {
            guard let entry = value as? [String: Any] else { continue }
            let cpu = entry["cpuKind"] as? String ?? "Unknown CPU"
            let model = entry["modelCode"] as? String ?? "Unknown"
            result[key] = "\(cpu), \(model)"
        }
        return result
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

    static func formatValue(_ value: Double, metricId: String) -> String {
        if metricId.contains("Memory") || metricId.contains("memory") {
            if value >= 1_000_000 {
                return String(format: "%.1f GB", value / 1_000_000)
            } else if value >= 1000 {
                return String(format: "%.0f kB", value)
            } else {
                return String(format: "%.0f bytes", value)
            }
        }

        if metricId.contains("time") || metricId.contains("Clock")
            || metricId.contains("Duration") || metricId.contains("duration")
        {
            if value >= 1.0 {
                return String(format: "%.3fs", value)
            } else {
                return String(format: "%.4fs", value)
            }
        }

        // Generic numeric
        if value == value.rounded(), value < 1_000_000 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4g", value)
    }

    static func formatPercent(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }
}
