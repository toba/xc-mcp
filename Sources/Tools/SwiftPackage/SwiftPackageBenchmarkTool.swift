import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Runs and gates a package-benchmark suite
///
/// The plugin invocation carries four traps, and each one fails in a way that reads as something
/// else: the working directory is the nested `Benchmarks` package rather than the repository root,
/// every SwiftPM option goes before the `benchmark` verb, a library that links a platform framework
/// needs an rpath the plugin does not add, and a filter that matches nothing exits 0 with no table.
/// This tool closes all four and returns the percentile figures as rows.
public struct SwiftPackageBenchmarkTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "subcommand": .object([
                "type": .string("string"),
                "description": .string(
                    "What to run. 'run' measures and reports the figures, and it is the default. 'list' names the benchmarks and measures nothing. 'thresholds_check' compares p90 against the recorded ceilings and returns the verdict. 'thresholds_update' rewrites every ceiling from this run, so run it only when a change is meant to move a figure.",
                ),
                "enum": .array(BenchmarkSubcommand.acceptedValues.map { Value.string($0) }),
            ]),
            "filter": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Regexes selecting which benchmarks run. \(BenchmarkResultFormatter.wholeMatchNote) A selection that matches nothing is reported as an error rather than an empty pass.",
                ),
            ]),
            "skip": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Regexes selecting which benchmarks to leave out. Whole-match, the same as filter.",
                ),
            ]),
            "metric": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string(
                    "Metric names that replace the ones the benchmarks declare, e.g. [\"mallocCountTotal\"] for an allocation-only pass on a loaded machine. An allocation count does not move with machine load, so this is the answer when wall clock is useless. Rejected with thresholds_update, which writes only the metrics the run measured and would delete every other ceiling.",
                ),
            ]),
            "deep": .object([
                "type": .string("boolean"),
                "description": .string(
                    "Run the long pass (DEEP_BENCHMARK=1): 3 warmups and 500 samples instead of 1 and 10. It costs minutes of machine time rather than seconds and holds the build lock against every other agent for all of them, so ask the user for it in the turn you run it. Defaults to false.",
                ),
            ]),
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }
        properties.merge(SwiftPackageToolSchema.timeout(for: "the benchmark run")) { current, _ in
            current
        }
        properties.merge(SwiftDiagnosticOptions.schemaProperties) { current, _ in current }
        properties.merge(SwiftBuildTraits.schemaProperties) { current, _ in current }

        return .init(
            name: "swift_package_benchmark",
            description:
                "Run or gate a package-benchmark suite. Point `package_path` at the repository and the tool finds the nested Benchmarks package itself, orders the SwiftPM options ahead of the plugin verb, and adds the platform-framework rpath a benchmark executable needs but does not get. A run returns one row per benchmark and metric with every percentile in raw units, so two runs compare without reading two ASCII tables. `thresholds_check` returns its verdict as a field, because the plugin prints `error: benchmarkThresholdImprovement` for a result better than the recorded ceiling and that word makes a win read as a failure. A benchmark run is a release build, so it takes the build lock like any other build.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let suite = try BenchmarkSuiteLocator.locate(packagePath: packagePath)
        let subcommand = try Self.parseSubcommand(from: arguments)
        let filter = arguments.getStringList("filter")
        let skip = arguments.getStringList("skip")
        let metrics = try Self.parseMetrics(from: arguments, subcommand: subcommand)
        let deep = arguments.getBool("deep")
        let traits = try await sessionManager.resolveTraits(from: arguments)
        let diagnostics = SwiftDiagnosticOptions(from: arguments)
        let explicitTimeout = arguments.explicitTimeout()

        let isCold = SwiftRunner.isColdCache(
            packagePath: suite.path, destination: .macOS, configuration: "release",
        )
        let timeout = explicitTimeout ?? Self.defaultTimeout(deep: deep, isCold: isCold)
        let environment = await Self.environment(
            sessionManager.resolveEnvironment(from: arguments), deep: deep,
        )

        // The session warmup builds the root package, which the nested suite depends on by path.
        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let platformFrameworks = await SwiftRunner.platformFrameworksPath()
        let context = Self.context(
            packagePath: packagePath, suite: suite, traits: traits, deep: deep,
            filter: filter, skip: skip, metrics: metrics,
        )
        let start = ContinuousClock.now

        let sink = try diagnostics.makeSink()
        // Pairing the close with the open covers every exit path, including one a later edit adds.
        defer { _ = sink?.finish() }
        let progress = SwiftDiagnosticOptions.combine(onProgress, sink)

        do {
            let result = try await swiftRunner.benchmark(
                suitePath: suite.path,
                subcommand: subcommand,
                filter: filter,
                skip: skip,
                metrics: metrics,
                traits: traits,
                swiftcFlags: diagnostics.swiftcFlags,
                platformFrameworksPath: platformFrameworks,
                environment: environment,
                timeout: timeout,
                onProgress: progress,
            )
            let sinkSummary = sink?.finish()
            let elapsed = start.duration(to: .now)

            var text = try Self.report(
                subcommand: subcommand, result: result, context: context, elapsed: elapsed,
                suite: suite, filter: filter, skip: skip,
            )
            if let warning = traits.replacedDefaultsWarning { text += "\n\(warning)\n" }
            if let sinkSummary { text += "\n\(sinkSummary.formatted())\n" }
            return CallTool.Result.text(text)
        } catch let ProcessError.timeout(duration) {
            throw MCPError.internalError(Self.timeoutMessage(
                duration: duration, suite: suite, deep: deep, isCold: isCold,
            ))
        } catch {
            throw try error.asMCPError()
        }
    }

    // MARK: - Reporting

    /// Builds the report for one finished command, or throws when the command failed.
    ///
    /// A threshold verdict is not a failure here. The plugin exits non-zero for an improvement as
    /// well as a regression, and both are answers the caller asked for.
    private static func report(
        subcommand: BenchmarkSubcommand,
        result: SwiftResult,
        context: String,
        elapsed: Duration,
        suite: BenchmarkSuiteLocator.Location,
        filter: [String],
        skip: [String],
    ) throws -> String {
        switch subcommand {
            case .list:
                let listings = BenchmarkOutputParser.listings(from: result.output)
                guard !listings.isEmpty else {
                    throw MCPError.internalError(emptySuiteMessage(
                        suite: suite, output: result.output,
                    ))
                }
                return BenchmarkResultFormatter.formatList(listings: listings, context: context)

            case .thresholdsCheck:
                let verdict = BenchmarkOutputParser.verdict(from: result.output)
                guard let verdict else {
                    throw MCPError.internalError(failureMessage(
                        subcommand: subcommand, result: result, suitePath: suite.path,
                    ))
                }
                return BenchmarkResultFormatter.formatCheck(
                    verdict: verdict,
                    deviations: BenchmarkResultFormatter.deviations(from: result.output),
                    context: context,
                    elapsed: elapsed,
                )

            case .thresholdsUpdate:
                guard result.succeeded else {
                    throw MCPError.internalError(failureMessage(
                        subcommand: subcommand, result: result, suitePath: suite.path,
                    ))
                }
                return formatUpdate(
                    suite: suite, context: context, elapsed: elapsed, output: result.output,
                )

            case .run:
                guard result.succeeded else {
                    throw MCPError.internalError(failureMessage(
                        subcommand: subcommand, result: result, suitePath: suite.path,
                    ))
                }
                let figures = BenchmarkOutputParser.figures(from: result.output)

                guard !figures.isEmpty else {
                    throw MCPError.internalError(noFiguresMessage(
                        suite: suite, filter: filter, skip: skip, output: result.output,
                    ))
                }
                return BenchmarkResultFormatter.formatRun(
                    figures: figures, context: context, elapsed: elapsed,
                )
        }
    }

    /// The report for a `thresholds update`, which writes files rather than reporting figures.
    private static func formatUpdate(
        suite: BenchmarkSuiteLocator.Location,
        context: String,
        elapsed: Duration,
        output: String,
    ) -> String {
        var text = "## Thresholds updated\n\n\(context)\n\(elapsed.elapsedDescription)\n\n"
        text += "Every threshold file was rewritten from this run, at "
        text += "`\(suite.path)/\(BenchmarkSuiteLocator.thresholdsDirectory)`.\n\n"
        text +=
            "Read the diff and separate the two kinds of movement. An allocation or instruction "
            + "count that moved is the change. A wall-clock ceiling that moved on a benchmark the "
            + "change does not touch is the machine, because the update rewrites every file from "
            + "one run.\n"
        let written = output.split(separator: "\n")
            .count(where: { $0.hasPrefix("Writing to ") })
        if written > 0 { text += "\n\(written) file\(written == 1 ? "" : "s") written.\n" }
        return text
    }

    /// The error text for a run that measured nothing.
    ///
    /// A filter that matches nothing exits 0 and prints no table, so a typo reads as a clean pass.
    /// Naming the benchmarks is the fix, and the threshold files name them without a second release
    /// build of the suite.
    static func noFiguresMessage(
        suite: BenchmarkSuiteLocator.Location,
        filter: [String],
        skip: [String],
        output: String,
    ) -> String {
        guard !filter.isEmpty || !skip.isEmpty else {
            return emptySuiteMessage(suite: suite, output: output)
        }
        var message = "The run measured nothing. "
        message += "\(BenchmarkResultFormatter.wholeMatchNote) "
        message += "Selected: filter \(filter), skip \(skip).\n"

        let recorded = BenchmarkSuiteLocator.recordedBenchmarks(suitePath: suite.path)
        let thresholds = "\(suite.path)/\(BenchmarkSuiteLocator.thresholdsDirectory)"

        guard !recorded.isEmpty else {
            message += "\n\(thresholds) names no benchmark either, so run the `list` subcommand "
                + "for the names the suite declares.\n"
            return message
        }
        message += "\nThe benchmarks with a recorded threshold are:\n"

        for entry in recorded {
            message += "\n\(entry.target):\n"
            for name in entry.benchmarks { message += "  \(name)\n" }
        }
        message += "\nThese names come from \(thresholds), so a benchmark with no recorded ceiling "
            + "yet is missing from the list. Run the `list` subcommand for the full set.\n"
        return message
    }

    /// The error text for a suite that reported no benchmark at all.
    private static func emptySuiteMessage(
        suite: BenchmarkSuiteLocator.Location,
        output: String,
    ) -> String {
        var message = "The suite at \(suite.path) reported no benchmark. "
        message +=
            "A benchmark executable that fails to load its libraries reports an empty list rather "
            + "than a link error, and the usual cause is a missing framework search path. "
        message += "Read the output below for a dyld message or a WaitPIDError.\n\n"
        message += Self.tail(of: output)
        return message
    }

    /// The error text for a command that failed for a reason other than a verdict.
    ///
    /// A benchmark run is a release build of the suite and its dependencies, so a compile error is
    /// the common failure and the plugin reports it as `error: buildFailed`. Parsing the output
    /// puts the diagnostics at the top of the message instead of somewhere inside a build log.
    static func failureMessage(
        subcommand: BenchmarkSubcommand,
        result: SwiftResult,
        suitePath: String,
    ) -> String {
        var message = "swift package benchmark"
        let verbs = subcommand.verbs.joined(separator: " ")
        if !verbs.isEmpty { message += " \(verbs)" }
        message += " failed"

        if let name = BenchmarkOutputParser.pluginError(in: result.output) {
            message += " (\(name))"
        }
        message += " with exit code \(result.exitCode).\n\n"

        let parsed = BuildOutputParser().parse(input: TerminalEscapes.stripped(result.output))
        // the plugin's own error line parses as an error, and the header above already names it
        let diagnostics = parsed.errors.filter {
            $0.file != nil || !BenchmarkOutputParser.pluginErrorNames.contains($0.message)
        }
        guard !diagnostics.isEmpty || !parsed.linkerErrors.isEmpty else {
            return message + tail(of: result.output)
        }
        return message
            + BuildResultFormatter.formatBuildResult(
                parsed, projectRoot: suitePath, errorsOnly: true,
            )
    }

    /// How much of a failed command's output a report carries
    private static let outputTailLimit = 6000

    /// The last of `output`, so a release build log does not fill the response.
    private static func tail(of output: String) -> String {
        let stripped = TerminalEscapes.stripped(output)
        guard stripped.count > outputTailLimit else { return stripped }
        return "…\n" + String(stripped.suffix(outputTailLimit))
    }

    /// The error text for a command that exceeded its deadline.
    private static func timeoutMessage(
        duration: Duration,
        suite: BenchmarkSuiteLocator.Location,
        deep: Bool,
        isCold: Bool,
    ) -> String {
        var message = "swift package benchmark timed out after \(duration) (suite: \(suite.path))."

        if deep {
            message +=
                " A deep pass measures 503 iterations of every selected benchmark, so narrow it "
                + "with `filter` or raise `timeout`."
        } else if isCold {
            message += " The suite's release build cache was empty, so the run compiled the whole "
                + "dependency graph first."
        }
        message += " Pass an explicit `timeout` (seconds) and retry."
        return message
    }

    // MARK: - Arguments

    /// The default deadline for a run the caller gave no timeout for.
    static func defaultTimeout(deep: Bool, isCold: Bool) -> Duration {
        deep || isCold ? SwiftRunner.deepBenchmarkTimeout : SwiftRunner.defaultTimeout
    }

    /// The variables a long pass adds to the environment.
    ///
    /// - Parameter deep: Whether the caller asked for the long pass.
    /// - Returns: The variables, empty for a short pass.
    static func deepEnvironmentOverrides(deep: Bool) -> [String: String] {
        deep ? [SwiftRunner.deepBenchmarkVariable: "1"] : [:]
    }

    /// Adds the long pass variables to the environment.
    ///
    /// The plugin passes its own environment down to the runner, which is how the variable reaches
    /// the benchmark executable.
    static func environment(_ base: Environment, deep: Bool) -> Environment {
        let overrides = deepEnvironmentOverrides(deep: deep)
        guard !overrides.isEmpty else { return base }

        var keyed: [Environment.Key: String?] = [:]
        for (key, value) in overrides { keyed[Environment.Key(stringLiteral: key)] = value }
        return base.updating(keyed)
    }

    /// Reads the `subcommand` argument.
    ///
    /// - Returns: The named verb, or ``BenchmarkSubcommand/run`` when the caller omits it.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the value names no known verb.
    static func parseSubcommand(
        from arguments: [String: Value],
    ) throws(MCPError) -> BenchmarkSubcommand {
        guard let raw = arguments.getNonEmptyString("subcommand") else { return .run }
        guard let subcommand = BenchmarkSubcommand(rawValue: raw) else {
            throw .invalidParams(
                "Unknown subcommand '\(raw)'. Accepted values: "
                    + "\(BenchmarkSubcommand.acceptedValues.joined(separator: ", ")).",
            )
        }
        return subcommand
    }

    /// Reads the `metric` argument and refuses a value the plugin would silently ignore.
    ///
    /// - Throws: ``MCPError/invalidParams(_:)`` when the caller names an unknown metric, or names
    ///   any metric alongside `thresholds_update`.
    static func parseMetrics(
        from arguments: [String: Value],
        subcommand: BenchmarkSubcommand,
    ) throws(MCPError) -> [String] {
        let metrics = arguments.getStringList("metric")
        guard !metrics.isEmpty else { return [] }

        if subcommand == .thresholdsUpdate {
            throw .invalidParams(
                "`metric` and `thresholds_update` cannot go together. The update writes only the "
                    + "metrics the run measured, so it would rewrite every file with the named "
                    + "metric alone and delete the other ceilings. Run thresholds_update bare.",
            )
        }
        let unknown = metrics.filter { !SwiftRunner.benchmarkMetricNames.contains($0) }
        guard unknown.isEmpty else {
            throw .invalidParams(
                "Unknown metric \(unknown.joined(separator: ", ")). The plugin turns an unknown "
                    + "name into a custom metric that nothing measures, so the run reports no "
                    + "figure and still exits 0. Accepted names: "
                    + "\(SwiftRunner.benchmarkMetricNames.sorted().joined(separator: ", ")).",
            )
        }
        return metrics
    }

    /// The line every report carries, naming what ran.
    static func context(
        packagePath: String,
        suite: BenchmarkSuiteLocator.Location,
        traits: SwiftBuildTraits,
        deep: Bool,
        filter: [String],
        skip: [String],
        metrics: [String],
    ) -> String {
        var parts = [packagePath, suite.label, traits.label, deep ? "deep pass" : "short pass"]
        if !filter.isEmpty { parts.append("filter \(filter.joined(separator: ", "))") }
        if !skip.isEmpty { parts.append("skip \(skip.joined(separator: ", "))") }
        if !metrics.isEmpty { parts.append("metrics \(metrics.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
    }
}
