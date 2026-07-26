import MCP
import XCMCPCore
import Foundation

/// Benchmarks build wall-clock time by running repeated clean and incremental builds.
///
/// `get_performance_metrics` covers XCTest `measure()` runtime only — there is no build-*time*
/// benchmark. This tool wraps `xcodebuild` with `-showBuildTimingSummary`, runs N clean builds and
/// N incremental (null) builds, and reports each series separately because they expose different
/// problems: clean-build time reflects the module graph / target structure, while incremental
/// (no-change) rebuild time reflects run-script phases and cache invalidation — a script phase with
/// no output paths, for example, re-runs every incremental build.
///
/// Results persist to a `.build-benchmark/` directory next to the project so a later run can diff
/// against the stored baseline ("apply a setting, re-benchmark" in one call).
public struct BenchmarkBuildTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    /// Upper bound on runs per series — a runaway guard so a typo can't queue dozens of builds.
    static let maxRunsPerSeries = 10

    public func tool() -> Tool {
        Tool(
            name: "benchmark_build",
            description:
                "Benchmark build wall-clock time by running repeated clean and incremental builds. "
                + "Reports clean-build and incremental (no-change) rebuild time separately — clean "
                + "reflects the module graph/target structure, incremental reflects run-script "
                + "phases and cache invalidation. Persists results to a .build-benchmark/ directory "
                + "and can diff against a saved baseline so 'apply a setting, re-benchmark' is one "
                + "call. Read-only apart from writing the baseline JSON.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to build. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration. Defaults to Debug (incremental-build anti-patterns "
                                + "are Debug-focused).",
                        ),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Architecture to build for (arm64 or x86_64). Defaults to the current "
                                + "machine's architecture.",
                        ),
                    ]),
                    "clean_runs": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of clean builds to time. Defaults to 3. Max 10.",
                        ),
                    ]),
                    "incremental_runs": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of incremental (no-change) rebuilds to time. Defaults to 3. Max "
                                + "10. A warm-up build runs first so the first sample is a true "
                                + "null build.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for each individual build. Defaults to 600.",
                        ),
                    ]),
                    "save_baseline": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, persist this run's results as the baseline for this "
                                + "scheme/configuration in .build-benchmark/.",
                        ),
                    ]),
                    "compare_baseline": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, diff this run against the previously saved baseline (if any) "
                                + "and report the percentage change.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments) ?? "Debug"
        let arch = arguments.getString("arch")

        let cleanRuns = min(
            max(arguments.getInt("clean_runs") ?? 3, 0), Self.maxRunsPerSeries,
        )
        let incrementalRuns = min(
            max(arguments.getInt("incremental_runs") ?? 3, 0), Self.maxRunsPerSeries,
        )
        guard cleanRuns > 0 || incrementalRuns > 0 else {
            throw MCPError.invalidParams(
                "At least one of clean_runs or incremental_runs must be greater than 0.",
            )
        }
        let timeout = TimeInterval(arguments.getInt("timeout") ?? 600)
        let saveBaseline = arguments.getBool("save_baseline")
        let compareBaseline = arguments.getBool("compare_baseline")

        var destination = XcodebuildRunner.macOSDestination
        if let arch { destination += ",arch=\(arch)" }

        // Scope DerivedData explicitly so every invocation (clean+build and incremental build) hits
        // the same directory. runner.clean() omits the destination and would otherwise resolve a
        // different, platform-unscoped path than the destination-scoped build.
        let scopedDerivedData = DerivedDataScoper.effectivePath(
            workspacePath: workspacePath, projectPath: projectPath, destination: destination,
        )

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )

        // Load the prior baseline before we overwrite anything.
        let anchorPath = projectPath ?? workspacePath
        let baselineURL = anchorPath.map {
            Self.baselineURL(anchorPath: $0, scheme: scheme, configuration: configuration)
        }
        let priorBaseline: BenchmarkRecord? =
            (compareBaseline && baselineURL != nil)
                ? Self.loadBaseline(at: baselineURL!) : nil

        var cleanSeconds: [Double] = []
        cleanSeconds.reserveCapacity(cleanRuns)
        var incrementalSeconds: [Double] = []
        incrementalSeconds.reserveCapacity(incrementalRuns)
        var lastTimingSummary: [TimingPhase] = []

        // Clean builds: a single `clean build` invocation each so cleaning and building share the
        // scoped DerivedData and the timing reflects a true cold build.
        for _ in 0 ..< cleanRuns {
            let args = xcodebuildArgs(
                projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
                configuration: configuration, destination: destination,
                scopedDerivedData: scopedDerivedData, actions: ["clean", "build"],
            )
            let (seconds, result) = try await timedRun(arguments: args, timeout: timeout)
            try ensureSucceeded(result, projectRoot: projectRoot, phase: "clean build")
            cleanSeconds.append(seconds)
            lastTimingSummary = Self.parseTimingSummary(result.output)
        }

        if incrementalRuns > 0 {
            // Ensure a full build exists so the first incremental sample is a real null build.
            if cleanRuns == 0 {
                let warmArgs = xcodebuildArgs(
                    projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
                    configuration: configuration, destination: destination,
                    scopedDerivedData: scopedDerivedData, actions: ["build"],
                )
                let warm = try await xcodebuildRunner.run(
                    arguments: warmArgs, timeout: timeout, outputTimeout: nil, onProgress: nil,
                )
                try ensureSucceeded(warm, projectRoot: projectRoot, phase: "warm-up build")
            }

            for _ in 0 ..< incrementalRuns {
                let args = xcodebuildArgs(
                    projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
                    configuration: configuration, destination: destination,
                    scopedDerivedData: scopedDerivedData, actions: ["build"],
                )
                let (seconds, result) = try await timedRun(arguments: args, timeout: timeout)
                try ensureSucceeded(result, projectRoot: projectRoot, phase: "incremental build")
                incrementalSeconds.append(seconds)
            }
        }

        // Persist baseline if requested.
        var savedTo: String?
        if saveBaseline, let baselineURL {
            let record = BenchmarkRecord(
                scheme: scheme, configuration: configuration,
                cleanSeconds: cleanSeconds, incrementalSeconds: incrementalSeconds,
                machine: MachineMetadata.current().cpuBrandString,
                timestamp: ISO8601DateFormatter().string(from: Date()),
            )
            savedTo = Self.saveBaseline(record, to: baselineURL)
        }

        let text = Self.formatReport(
            scheme: scheme, configuration: configuration,
            cleanSeconds: cleanSeconds, incrementalSeconds: incrementalSeconds,
            timingSummary: lastTimingSummary, priorBaseline: priorBaseline,
            savedTo: savedTo,
        )
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Build invocation

    private func xcodebuildArgs(
        projectPath: String?, workspacePath: String?, scheme: String,
        configuration: String, destination: String,
        scopedDerivedData: String?, actions: [String],
    ) -> [String] {
        var args: [String] = []
        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }
        if let scopedDerivedData {
            args += ["-derivedDataPath", scopedDerivedData]
        }
        args += ["-scheme", scheme, "-destination", destination]
        args += ["-configuration", configuration]
        args += actions
        args += ["-showBuildTimingSummary"]
        return args
    }

    private func timedRun(
        arguments: [String], timeout: TimeInterval,
    ) async throws -> (seconds: Double, result: XcodebuildResult) {
        let start = ContinuousClock.now
        let result = try await xcodebuildRunner.run(
            arguments: arguments, timeout: timeout, outputTimeout: nil, onProgress: nil,
        )
        let elapsed = start.duration(to: .now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        return (seconds, result)
    }

    private func ensureSucceeded(
        _ result: XcodebuildResult, projectRoot: String?, phase: String,
    ) throws {
        guard !result.succeeded else { return }
        let errors = ErrorExtractor.extractBuildErrors(
            from: result.output, projectRoot: projectRoot, errorsOnly: true,
        )
        throw MCPError.internalError(
            "Benchmark aborted — a \(phase) failed:\n\n"
                + (errors.isEmpty ? String(result.output.suffix(2000)) : errors),
        )
    }

    // MARK: - Baseline storage

    /// Stored benchmark record for one scheme/configuration.
    struct BenchmarkRecord: Codable, Sendable {
        var scheme: String
        var configuration: String
        var cleanSeconds: [Double]
        var incrementalSeconds: [Double]
        var machine: String
        var timestamp: String
    }

    static func baselineURL(
        anchorPath: String, scheme: String, configuration: String,
    ) -> URL {
        let dir = URL(fileURLWithPath: anchorPath)
            .deletingLastPathComponent()
            .appendingPathComponent(".build-benchmark")
        let slug = "\(scheme)_\(configuration)"
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .joined(separator: "-")
        return dir.appendingPathComponent("\(slug).json")
    }

    static func loadBaseline(at url: URL) -> BenchmarkRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BenchmarkRecord.self, from: data)
    }

    /// Persists the record and returns the path written, or nil on failure.
    static func saveBaseline(_ record: BenchmarkRecord, to url: URL) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            )
            try encoder.encode(record).write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    // MARK: - Statistics

    struct BenchmarkStats: Sendable, Equatable {
        let count: Int
        let mean: Double
        let min: Double
        let max: Double
        let stddev: Double
    }

    static func stats(_ samples: [Double]) -> BenchmarkStats? {
        guard !samples.isEmpty else { return nil }
        let n = Double(samples.count)
        let mean = samples.reduce(0, +) / n
        let variance = samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        return BenchmarkStats(
            count: samples.count, mean: mean,
            min: samples.min() ?? mean, max: samples.max() ?? mean,
            stddev: variance.squareRoot(),
        )
    }

    // MARK: - Timing summary parsing

    struct TimingPhase: Sendable, Equatable {
        let phase: String
        let tasks: Int
        let seconds: Double
    }

    /// Parses `-showBuildTimingSummary` lines, e.g. `CompileSwiftSources (12 tasks) | 34.5 seconds`.
    static func parseTimingSummary(_ output: String) -> [TimingPhase] {
        let pattern = #/^\s*(\S.*?)\s+\((\d+)\s+tasks?\)\s*\|\s*([\d.]+)\s*seconds\s*$/#
        var phases: [TimingPhase] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let match = String(line).firstMatch(of: pattern),
                  let tasks = Int(match.2), let seconds = Double(match.3)
            else { continue }
            phases.append(
                TimingPhase(phase: String(match.1), tasks: tasks, seconds: seconds),
            )
        }
        return phases.sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Formatting

    static func formatSeconds(_ value: Double) -> String {
        String(format: "%.2fs", value)
    }

    static func formatReport(
        scheme: String, configuration: String,
        cleanSeconds: [Double], incrementalSeconds: [Double],
        timingSummary: [TimingPhase], priorBaseline: BenchmarkRecord?,
        savedTo: String?,
    ) -> String {
        var text = "## Build Benchmark\n\n"
        text += "**Scheme:** \(scheme)  **Configuration:** \(configuration)\n\n"

        text += formatSeries(
            title: "Clean builds", samples: cleanSeconds,
            baseline: priorBaseline?.cleanSeconds,
        )
        text += formatSeries(
            title: "Incremental (no-change) rebuilds", samples: incrementalSeconds,
            baseline: priorBaseline?.incrementalSeconds,
        )

        if !timingSummary.isEmpty {
            text += "\n### Slowest phases (last clean build)\n\n"
            for phase in timingSummary.prefix(8) {
                text += "  \(formatSeconds(phase.seconds).padding(toLength: 9, withPad: " ", startingAt: 0))"
                text += "\(phase.phase) (\(phase.tasks) task\(phase.tasks == 1 ? "" : "s"))\n"
            }
        }

        if let priorBaseline {
            text += "\n_Compared against baseline recorded \(priorBaseline.timestamp)"
            if !priorBaseline.machine.isEmpty { text += " on \(priorBaseline.machine)" }
            text += "._\n"
        }
        if let savedTo {
            text += "\nBaseline saved to `\(savedTo)`.\n"
        }
        return text
    }

    private static func formatSeries(
        title: String, samples: [Double], baseline: [Double]?,
    ) -> String {
        guard let series = stats(samples) else { return "" }
        var text = "### \(title)\n\n"
        text += "  runs: \(series.count)  "
        text += "mean: \(formatSeconds(series.mean))  "
        text += "min: \(formatSeconds(series.min))  "
        text += "max: \(formatSeconds(series.max))  "
        text += "stddev: \(formatSeconds(series.stddev))\n"

        if let baseline, let baseStats = stats(baseline) {
            let delta = series.mean - baseStats.mean
            let pct = baseStats.mean > 0 ? delta / baseStats.mean * 100 : 0
            let arrow = delta < 0 ? "▼ faster" : (delta > 0 ? "▲ slower" : "no change")
            text += "  vs baseline mean \(formatSeconds(baseStats.mean)): "
            text += String(format: "%+.2fs (%+.1f%%) %@", delta, pct, arrow) + "\n"
        }
        text += "\n"
        return text
    }
}
