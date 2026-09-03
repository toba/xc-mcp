import Foundation
import Subprocess

/// One `swift package benchmark` verb
///
/// The plugin implies `run` when no verb appears, and the `thresholds` verbs take a second word.
/// The raw value is the tool argument a caller passes.
public enum BenchmarkSubcommand: String, Sendable, CaseIterable {
    /// Measure every selected benchmark and report the figures
    case run

    /// Print the benchmark names and measure nothing
    case list

    /// Compare the p90 figures against the recorded ceilings
    case thresholdsCheck = "thresholds_check"

    /// Rewrite every ceiling from this run
    case thresholdsUpdate = "thresholds_update"

    /// The accepted `subcommand` values, in schema order
    public static let acceptedValues: [String] = allCases.map(\.rawValue)

    /// The words that follow the `benchmark` verb
    public var verbs: [String] {
        switch self {
            case .run: []
            case .list: ["list"]
            case .thresholdsCheck: ["thresholds", "check"]
            case .thresholdsUpdate: ["thresholds", "update"]
        }
    }

    /// Whether the command writes into the package directory, which SwiftPM gates behind a flag
    public var writesPackageDirectory: Bool { self == .thresholdsUpdate }
}

public extension SwiftRunner {
    /// The metric names the plugin recognizes.
    ///
    /// A name outside this set becomes a custom metric that nothing measures, so the run reports no
    /// figure for it and still exits 0. Validating the name before the run turns that silence into
    /// an error.
    ///
    /// The names come from `BenchmarkOutputParser.metricDisplayNames`, which is the one list. A
    /// second copy here would let a new metric pass validation and then report under the plugin's
    /// display label, or fail validation the plugin would have accepted.
    static let benchmarkMetricNames = Set(BenchmarkOutputParser.metricDisplayNames.map(\.raw))

    /// The environment variable that turns the short pass into the long one
    static let deepBenchmarkVariable = "DEEP_BENCHMARK"

    /// Timeout for a deep pass, which turns seconds of measurement into minutes (15 minutes)
    static var deepBenchmarkTimeout: Duration { coldCacheTimeout }

    /// Builds the `swift package benchmark` argument list.
    ///
    /// Every SwiftPM option goes before the `benchmark` verb and every plugin option goes after it.
    /// The plugin rejects a SwiftPM option that follows the verb as an unknown option.
    ///
    /// - Parameters:
    ///   - subcommand: The verb to run.
    ///   - filter: Whole-match regexes selecting which benchmarks run.
    ///   - skip: Whole-match regexes selecting which benchmarks to leave out.
    ///   - metrics: Metric names that replace the ones the benchmarks declare.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    ///   - platformFrameworksPath: Directory to add to the runtime search path, or `nil` to add
    ///     none. See ``platformFrameworksPath()``.
    /// - Returns: The argument list, `swift` itself excluded.
    static func benchmarkArguments(
        subcommand: BenchmarkSubcommand,
        filter: [String] = [],
        skip: [String] = [],
        metrics: [String] = [],
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        platformFrameworksPath: String? = nil,
    ) -> [String] {
        var args = ["package"]
        args.append(contentsOf: traits.arguments)
        args.append(contentsOf: swiftcArguments(swiftcFlags))

        if let platformFrameworksPath {
            args.append(contentsOf: ["-Xlinker", "-rpath", "-Xlinker", platformFrameworksPath])
        }
        if subcommand.writesPackageDirectory { args.append("--allow-writing-to-package-directory") }
        args.append("benchmark")
        args.append(contentsOf: subcommand.verbs)

        for pattern in filter { args.append(contentsOf: ["--filter", pattern]) }
        for pattern in skip { args.append(contentsOf: ["--skip", pattern]) }
        for metric in metrics { args.append(contentsOf: ["--metric", metric]) }
        args.append("--no-progress")

        // The influx export carries every percentile of every metric, and `stdout` keeps it out of
        // a file the plugin would need write permission for. The other verbs print their own
        // report.
        if subcommand == .run {
            args.append(contentsOf: ["--format", "influx", "--path", "stdout"])
        }
        return args
    }

    /// Runs one `swift package benchmark` command.
    ///
    /// - Parameters:
    ///   - suitePath: The directory that holds the suite's `Package.swift`, which is the nested
    ///     `Benchmarks` package for a shared package. See ``BenchmarkSuiteLocator``.
    ///   - subcommand: The verb to run.
    ///   - filter: Whole-match regexes selecting which benchmarks run.
    ///   - skip: Whole-match regexes selecting which benchmarks to leave out.
    ///   - metrics: Metric names that replace the ones the benchmarks declare.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    ///   - platformFrameworksPath: Directory to add to the runtime search path.
    ///   - environment: Environment variables for the subprocess.
    ///   - timeout: Maximum time to wait.
    /// - Returns: The command result containing exit code and output.
    func benchmark(
        suitePath: String,
        subcommand: BenchmarkSubcommand,
        filter: [String] = [],
        skip: [String] = [],
        metrics: [String] = [],
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        platformFrameworksPath: String? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        let result = try await run(
            arguments: Self.benchmarkArguments(
                subcommand: subcommand, filter: filter, skip: skip, metrics: metrics,
                traits: traits, swiftcFlags: swiftcFlags,
                platformFrameworksPath: platformFrameworksPath,
            ),
            workingDirectory: suitePath,
            environment: environment,
            timeout: timeout,
            onProgress: onProgress,
        )
        RawBuildLog.store(
            rawOutput: result.output,
            action: "swift package benchmark \(subcommand.verbs.joined(separator: " "))",
            destination: SwiftBuildDestination.hostLabel,
            succeeded: result.succeeded,
        )
        return result
    }

    /// The directory that holds the platform frameworks, such as `Testing.framework`.
    ///
    /// SwiftPM puts that directory on the runtime search path of a test product alone. A benchmark
    /// executable is not one, so a library that links `Testing.framework` fails to load and the
    /// plugin reports an empty benchmark list rather than a link error. Passing the directory as an
    /// rpath costs a suite that needs nothing from it a search path it never reads.
    ///
    /// `DYLD_FRAMEWORK_PATH` does not substitute. The plugin spawns the runner through a signed
    /// system binary, and the kernel strips every `DYLD_` variable from that spawn.
    ///
    /// - Returns: The directory, or `nil` when `xcrun` reports nothing or the directory is absent.
    static func platformFrameworksPath() async -> String? {
        guard let result = try? await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["--show-sdk-platform-path"]),
            timeout: .seconds(60),
        ) else { return nil }

        let platform = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.succeeded, !platform.isEmpty else { return nil }

        let frameworks = URL(fileURLWithPath: platform)
            .appendingPathComponent("Developer/Library/Frameworks").path
        guard FileManager.default.fileExists(atPath: frameworks) else { return nil }
        return frameworks
    }
}
