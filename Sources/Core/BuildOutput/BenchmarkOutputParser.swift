import Foundation

/// One percentile of one measured metric
public struct BenchmarkPercentile: Sendable, Equatable {
    /// The percentile label, such as `p90`
    public let label: String

    /// The raw figure, in the metric's own unit
    public let value: Int

    public init(label: String, value: Int) {
        self.label = label
        self.value = value
    }
}

/// One metric of one benchmark, with every percentile the run recorded
///
/// The figures are raw. A time metric counts nanoseconds and every other metric counts occurrences,
/// which is what a threshold file records and what `thresholds check` compares.
public struct BenchmarkFigure: Sendable, Equatable {
    /// The benchmark target, such as `TobaCoreBenchmarks`
    public let target: String

    /// The benchmark name
    public let benchmark: String

    /// The metric name the plugin accepts on the command line, such as `mallocCountTotal`
    public let metric: String

    /// Whether the figures count nanoseconds rather than occurrences
    public let isTime: Bool

    /// Every percentile the run recorded, in the order the plugin reported them
    public let percentiles: [BenchmarkPercentile]

    /// How many samples the run measured
    public let samples: Int

    /// How many warmup iterations ran before the samples
    public let warmups: Int

    /// The figure `thresholds check` compares, which is the p90 alone
    public var p90: Int? { percentiles.first { $0.label == "p90" }?.value }

    /// The unit a report prints beside the figures
    public var unit: String { isTime ? "ns" : "count" }
}

/// What `thresholds check` decided
public enum BenchmarkThresholdVerdict: String, Sendable, Equatable {
    /// Nothing moved
    case equal

    /// A figure beat its recorded ceiling, which the plugin reports as an error
    case improvement

    /// A figure exceeded its recorded ceiling
    case regression
}

/// One benchmark target and the benchmarks it declares
public struct BenchmarkListing: Sendable, Equatable {
    public let target: String
    public let benchmarks: [String]

    public init(target: String, benchmarks: [String]) {
        self.target = target
        self.benchmarks = benchmarks
    }
}

/// Reads what `swift package benchmark` printed
///
/// A run exports its figures as an influx CSV, which carries every percentile of every metric. The
/// other verbs print prose, so each one has its own reader here.
public enum BenchmarkOutputParser {
    /// The metric names the plugin prints, keyed by the name it accepts on the command line.
    ///
    /// The influx export labels a metric with its display name and strips the spaces out of it, so
    /// a caller reading the CSV never sees the name it passed to `--metric`. This table maps the
    /// one back to the other. The `isTime` flag records which metrics count nanoseconds.
    ///
    /// A label absent from the table reaches a report unchanged, which is what a custom metric
    /// needs.
    ///
    /// This is the one list of metric names. The label index below and the set of names the tool
    /// validates against both derive from it, so a new metric goes in here alone.
    static let metricDisplayNames: [(raw: String, display: String, isTime: Bool)] = [
        ("cpuUser", "Time (user CPU)", true),
        ("cpuSystem", "Time (system CPU)", true),
        ("cpuTotal", "Time (total CPU)", true),
        ("wallClock", "Time (wall clock)", true),
        ("throughput", "Throughput (# / s)", false),
        ("peakMemoryResident", "Memory (resident peak)", false),
        ("peakMemoryResidentDelta", "Memory Δ (resident peak)", false),
        ("peakMemoryVirtual", "Memory (virtual peak)", false),
        ("mallocCountSmall", "Malloc (small)", false),
        ("mallocCountLarge", "Malloc (large)", false),
        ("mallocCountTotal", "Malloc (total)", false),
        ("freeCountTotal", "Free (total)", false),
        ("mallocBytesCount", "Malloc (bytes total)", false),
        ("mallocFreeDelta", "Malloc / free Δ", false),
        ("allocatedResidentMemory", "Memory (allocated resident)", false),
        ("memoryLeaked", "Memory leaked (resident)", false),
        ("memoryLeakedBytes", "Malloc / free Δ (bytes)", false),
        ("syscalls", "Syscalls (total)", false),
        ("contextSwitches", "Context switches", false),
        ("threads", "Threads (peak)", false),
        ("threadsRunning", "Threads (running)", false),
        ("readSyscalls", "Syscalls (read)", false),
        ("writeSyscalls", "Syscalls (write)", false),
        ("readBytesLogical", "Bytes (read logical)", false),
        ("writeBytesLogical", "Bytes (write logical)", false),
        ("readBytesPhysical", "Bytes (read physical)", false),
        ("writeBytesPhysical", "Bytes (write physical)", false),
        ("instructions", "Instructions", false),
        ("objectAllocCount", "Object allocs", false),
        ("retainCount", "Retains", false),
        ("releaseCount", "Releases", false),
        ("retainReleaseDelta", "(Alloc + Retain) - Release Δ", false),
    ]

    /// The metric table keyed by the label the export writes, which is the display name with its
    /// spaces removed.
    ///
    /// The export writes one line per benchmark, metric and percentile, so a run of a modest suite
    /// asks this question hundreds of times. Stripping the spaces once per metric rather than once
    /// per question keeps that off the hot path.
    static let metricsByDisplayLabel: [String: (raw: String, isTime: Bool)] = {
        var index = [String: (raw: String, isTime: Bool)](minimumCapacity: metricDisplayNames.count)
        for entry in metricDisplayNames {
            index[entry.display.filter { !$0.isWhitespace }] = (entry.raw, entry.isTime)
        }
        return index
    }()

    /// The metric name and time flag for one space-stripped display label.
    ///
    /// - Parameter label: The label the influx export wrote.
    /// - Returns: The command-line name, or `label` itself when the table holds no match.
    static func metric(forDisplayLabel label: String) -> (raw: String, isTime: Bool) {
        metricsByDisplayLabel[label] ?? (label, false)
    }

    /// The number of fields one influx data line carries
    private static let influxFieldCount = 15

    /// Reads the figures out of an influx CSV export.
    ///
    /// The export writes one line per target, benchmark, metric and percentile. This groups those
    /// lines back into one figure per metric. Lines the build printed around the CSV never parse,
    /// so they are dropped rather than rejected.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: The figures, in the order the export wrote them.
    public static func figures(from output: String) -> [BenchmarkFigure] {
        // The key preserves first-seen order, so the report follows the plugin's own ordering.
        var order: [String] = []
        var grouped: [String: PartialFigure] = [:]

        for line in TerminalEscapes.stripped(output).split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("#"), !text.hasPrefix("measurement,")
            else { continue }
            let fields = csvFields(text)
            guard fields.count == influxFieldCount,
                  let value = Int(fields[10]),
                  let samples = Int(fields[12]),
                  let warmups = Int(fields[13]) else { continue }

            let resolved = Self.metric(forDisplayLabel: fields[6])
            let key = "\(fields[0])\u{0}\(fields[8])\u{0}\(resolved.raw)"

            if grouped[key] == nil {
                order.append(key)
                grouped[key] = PartialFigure(
                    target: fields[0], benchmark: fields[8], metric: resolved.raw,
                    isTime: resolved.isTime, samples: samples, warmups: warmups,
                )
            }
            grouped[key]?.percentiles.append(BenchmarkPercentile(
                label: percentileLabel(fields[9]), value: value))
        }
        return order.compactMap { grouped[$0]?.finished }
    }

    /// A figure under construction, before its percentile lines are all read
    private struct PartialFigure {
        let target: String
        let benchmark: String
        let metric: String
        let isTime: Bool
        let samples: Int
        let warmups: Int
        var percentiles: [BenchmarkPercentile] = []

        var finished: BenchmarkFigure {
            .init(
                target: target, benchmark: benchmark, metric: metric, isTime: isTime,
                percentiles: percentiles, samples: samples, warmups: warmups,
            )
        }
    }

    /// Turns the export's percentile column into a label, so `90.0` reads as `p90`.
    static func percentileLabel(_ raw: String) -> String {
        let trimmed = raw.hasSuffix(".0") ? String(raw.dropLast(2)) : raw
        return "p\(trimmed)"
    }

    /// Splits one CSV line, keeping a quoted field whole.
    ///
    /// The export quotes a benchmark name that holds a comma, so a plain split on the separator
    /// would break that line into the wrong number of fields.
    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false

        for character in line {
            switch character {
                case "\"": quoted.toggle()
                case "," where !quoted:
                    fields.append(current)
                    current = ""
                default: current.append(character)
            }
        }
        fields.append(current)
        return fields
    }

    /// Reads the verdict out of a `thresholds check` run.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: The verdict, or `nil` when the check never reached a comparison.
    public static func verdict(from output: String) -> BenchmarkThresholdVerdict? {
        let text = TerminalEscapes.stripped(output)

        if text.contains("WORSE than the defined thresholds")
            || text.contains("benchmarkThresholdRegression") { return .regression }

        if text.contains("BETTER than the defined thresholds")
            || text.contains("benchmarkThresholdImprovement") { return .improvement }

        return text.contains("EQUAL to the defined thresholds") ? .equal : nil
    }

    /// The header that opens one target's block in a `benchmark list` run
    private static let listHeaderPrefix = "Target '"

    /// Reads the benchmark names out of a `benchmark list` run.
    ///
    /// The plugin prints one header per target and then one name per line, until a blank line ends
    /// the block.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: One entry per target that reported at least one name.
    public static func listings(from output: String) -> [BenchmarkListing] {
        var listings: [BenchmarkListing] = []
        var target: String?
        var names: [String] = []

        func close() {
            if let target, !names.isEmpty {
                listings.append(BenchmarkListing(target: target, benchmarks: names))
            }
            target = nil
            names = []
        }

        for line in TerminalEscapes.stripped(output).split(
            separator: "\n", omittingEmptySubsequences: false,
        ) {
            let text = line.trimmingCharacters(in: .whitespaces)

            if text.hasPrefix(listHeaderPrefix), text.hasSuffix("available benchmarks:") {
                close()
                target = String(text.dropFirst(listHeaderPrefix.count).prefix { $0 != "'" })
                continue
            }
            guard target != nil else { continue }

            if text.isEmpty {
                close()
                continue
            }
            names.append(text)
        }
        close()
        return listings
    }

    /// The plugin error names, which SwiftPM prints as `error: <name>`.
    ///
    /// `benchmarkThresholdImprovement` is the one that misleads: it names a result better than the
    /// recorded ceiling, so the word `error` describes a win.
    public static let pluginErrorNames = [
        "benchmarkThresholdImprovement", "benchmarkThresholdRegression",
        "benchmarkCrashed", "benchmarkUnexpectedReturnCode",
        "baselineNotFound", "noPermissions", "invalidArgument", "buildFailed",
    ]

    /// Reads the plugin error name out of a failed run.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: The name, or `nil` when the output names none.
    public static func pluginError(in output: String) -> String? {
        let text = TerminalEscapes.stripped(output)
        return pluginErrorNames.first { text.contains("error: \($0)") }
    }
}
