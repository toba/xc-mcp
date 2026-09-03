import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

/// Tests for the `swift package benchmark` argument list and the arguments the tool refuses.
///
/// Option placement is the whole surface here. The plugin rejects a SwiftPM option that follows the
/// `benchmark` verb, and SwiftPM rejects a plugin option that precedes it.
struct SwiftPackageBenchmarkArgumentTests {
    /// Returns the argument that follows `flag`, or `nil` when the flag is absent.
    private func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Returns the index of the `benchmark` verb, which splits the two option namespaces.
    private func verbIndex(in args: [String]) -> Int {
        args.firstIndex(of: "benchmark") ?? args.count
    }

    // MARK: - Option placement

    @Test
    func `a write permission flag goes before the benchmark verb`() throws {
        let args = SwiftRunner.benchmarkArguments(subcommand: .thresholdsUpdate)
        let flag = try #require(args.firstIndex(of: "--allow-writing-to-package-directory"))

        #expect(flag < verbIndex(in: args))
    }

    @Test
    func `a run asks for no write permission`() {
        let args = SwiftRunner.benchmarkArguments(subcommand: .run)

        #expect(!args.contains("--allow-writing-to-package-directory"))
    }

    @Test
    func `the trait flags go before the benchmark verb`() throws {
        let args = SwiftRunner.benchmarkArguments(
            subcommand: .run, traits: .named(["defaults", "MacroTesting"]),
        )
        let flag = try #require(args.firstIndex(of: "--traits"))

        #expect(flag < verbIndex(in: args))
        #expect(value(after: "--traits", in: args) == "defaults,MacroTesting")
    }

    @Test
    func `the rpath flags go before the benchmark verb`() throws {
        let path = "/Platforms/MacOSX.platform/Developer/Library/Frameworks"
        let args = SwiftRunner.benchmarkArguments(subcommand: .run, platformFrameworksPath: path)
        let flag = try #require(args.firstIndex(of: "-rpath"))

        #expect(flag < verbIndex(in: args))
        #expect(args.contains(path))
        #expect(args.count(where: { $0 == "-Xlinker" }) == 2)
    }

    @Test
    func `no platform directory adds no rpath`() {
        let args = SwiftRunner.benchmarkArguments(subcommand: .run)

        #expect(!args.contains("-rpath"))
        #expect(!args.contains("-Xlinker"))
    }

    @Test
    func `each compiler flag goes before the verb with its own -Xswiftc`() throws {
        let args = SwiftRunner.benchmarkArguments(
            subcommand: .run, swiftcFlags: ["-enable-testing"],
        )
        let flag = try #require(args.firstIndex(of: "-enable-testing"))

        #expect(flag < verbIndex(in: args))
        #expect(args.contains("-Xswiftc"))
    }

    @Test
    func `the plugin options go after the benchmark verb`() throws {
        let args = SwiftRunner.benchmarkArguments(
            subcommand: .run, filter: ["Decode.*"], skip: ["Slow.*"],
            metrics: ["mallocCountTotal"],
        )
        let verb = verbIndex(in: args)

        for option in ["--filter", "--skip", "--metric", "--no-progress"] {
            let index = try #require(args.firstIndex(of: option))
            #expect(index > verb)
        }
    }

    // MARK: - Verbs

    @Test
    func `a run names no verb, which the plugin implies`() {
        let args = SwiftRunner.benchmarkArguments(subcommand: .run)

        #expect(args.first == "package")
        #expect(args[1] == "benchmark")
        #expect(args[2].hasPrefix("--"))
    }

    @Test
    func `a threshold verb takes two words`() {
        let check = SwiftRunner.benchmarkArguments(subcommand: .thresholdsCheck)
        let verb = verbIndex(in: check)

        #expect(check[verb + 1] == "thresholds")
        #expect(check[verb + 2] == "check")
        #expect(SwiftRunner.benchmarkArguments(subcommand: .thresholdsUpdate).contains("update"))
    }

    @Test
    func `a list run names the list verb`() {
        let args = SwiftRunner.benchmarkArguments(subcommand: .list)

        #expect(args[verbIndex(in: args) + 1] == "list")
    }

    // MARK: - Export format

    @Test
    func `a run exports the percentiles to stdout`() {
        let args = SwiftRunner.benchmarkArguments(subcommand: .run)

        #expect(value(after: "--format", in: args) == "influx")
        #expect(value(after: "--path", in: args) == "stdout")
    }

    @Test
    func `a verb that prints its own report asks for no export`() {
        for subcommand in [BenchmarkSubcommand.list, .thresholdsCheck, .thresholdsUpdate] {
            #expect(!SwiftRunner.benchmarkArguments(subcommand: subcommand).contains("--format"))
        }
    }

    @Test
    func `a repeated filter becomes a repeated option`() {
        let args = SwiftRunner.benchmarkArguments(
            subcommand: .run, filter: ["Decode.*", "Encode.*"],
        )

        #expect(args.count(where: { $0 == "--filter" }) == 2)
        #expect(args.contains("Encode.*"))
    }

    // MARK: - Refused arguments

    @Test
    func `an allocation-only threshold update is refused`() {
        #expect(throws: MCPError.self) {
            try SwiftPackageBenchmarkTool.parseMetrics(
                from: ["metric": .array([.string("mallocCountTotal")])],
                subcommand: .thresholdsUpdate,
            )
        }
    }

    @Test
    func `an unknown metric name is refused`() {
        #expect(throws: MCPError.self) {
            try SwiftPackageBenchmarkTool.parseMetrics(
                from: ["metric": .array([.string("mallocCountTotals")])],
                subcommand: .run,
            )
        }
    }

    @Test
    func `a known metric name passes through`() throws {
        let metrics = try SwiftPackageBenchmarkTool.parseMetrics(
            from: ["metric": .array([.string("mallocCountTotal"), .string("instructions")])],
            subcommand: .run,
        )

        #expect(metrics == ["mallocCountTotal", "instructions"])
    }

    @Test
    func `an unknown subcommand is refused`() {
        let arguments: [String: Value] = ["subcommand": .string("check")]

        #expect(throws: MCPError.self) {
            try SwiftPackageBenchmarkTool.parseSubcommand(from: arguments)
        }
    }

    @Test
    func `an omitted subcommand runs the benchmarks`() throws {
        #expect(try SwiftPackageBenchmarkTool.parseSubcommand(from: [String: Value]()) == .run)
    }

    // MARK: - One pattern or a list

    @Test
    func `one pattern written as a string reaches the list`() {
        let arguments: [String: Value] = ["filter": .string("Decode.*")]

        #expect(arguments.getStringList("filter") == ["Decode.*"])
    }

    @Test
    func `an absent key yields no pattern`() {
        #expect([String: Value]().getStringList("filter").isEmpty)
    }

    @Test
    func `an empty element is dropped`() {
        let arguments: [String: Value] = ["filter": .array([.string(""), .string("A.*")])]

        #expect(arguments.getStringList("filter") == ["A.*"])
    }

    // MARK: - Deadline and environment

    @Test
    func `a deep pass takes the long deadline`() {
        #expect(
            SwiftPackageBenchmarkTool.defaultTimeout(
                deep: true, isCold: false)
                == SwiftRunner.deepBenchmarkTimeout,
        )
        #expect(
            SwiftPackageBenchmarkTool.defaultTimeout(
                deep: false, isCold: false)
                == SwiftRunner.defaultTimeout,
        )
        #expect(
            SwiftPackageBenchmarkTool.defaultTimeout(
                deep: false, isCold: true)
                == SwiftRunner.deepBenchmarkTimeout,
        )
    }

    @Test
    func `the long pass is opt-in through the environment`() {
        #expect(
            SwiftPackageBenchmarkTool.deepEnvironmentOverrides(
                deep: true)
                == ["DEEP_BENCHMARK": "1"],
        )
        #expect(SwiftPackageBenchmarkTool.deepEnvironmentOverrides(deep: false).isEmpty)
    }
}

/// Tests for the text the tool returns when a command fails.
///
/// Both messages answer the same question: what does the caller do next. Naming the benchmarks and
/// naming the compiler errors are the two answers, and neither one costs a second build.
@Suite(.temporaryDirectory)
struct SwiftPackageBenchmarkMessageTests {
    /// A suite location under the test's own temporary directory
    private var suite: BenchmarkSuiteLocator.Location {
        .init(path: TemporaryDirectory.path, isNested: true)
    }

    /// Writes one empty threshold file into the test's own suite directory.
    private func recordThreshold(_ file: String) throws {
        let directory = TemporaryDirectory.url.appendingPathComponent("Thresholds")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent(file))
    }

    @Test
    func `a filter that matched nothing names the recorded benchmarks`() throws {
        try recordThreshold("ProbeBenchmarks.ObservationStart.p90.json")
        let message = SwiftPackageBenchmarkTool.noFiguresMessage(
            suite: suite, filter: ["Observation"], skip: [], output: "Build complete!",
        )

        #expect(message.contains("ObservationStart"))
        #expect(message.contains("ProbeBenchmarks"))
        #expect(message.contains("whole name must match"))
    }

    @Test
    func `a suite with no threshold file points at the list subcommand`() {
        let message = SwiftPackageBenchmarkTool.noFiguresMessage(
            suite: suite, filter: ["Observation"], skip: [], output: "Build complete!",
        )

        #expect(message.contains("`list`"))
        #expect(!message.contains("The benchmarks with a recorded threshold"))
    }

    @Test
    func `a run with no filter reports the empty suite instead`() {
        let message = SwiftPackageBenchmarkTool.noFiguresMessage(
            suite: suite, filter: [], skip: [], output: "dyld: Library not loaded",
        )

        #expect(message.contains("reported no benchmark"))
        #expect(message.contains("dyld"))
    }

    @Test
    func `a compile failure reports the diagnostics rather than the log tail`() {
        let output = """
            Building for production...
            /probe/Sources/Bench.swift:12:5: error: cannot find 'missing' in scope
            error: buildFailed
            """
        let message = SwiftPackageBenchmarkTool.failureMessage(
            subcommand: .run, result: .init(exitCode: 1, stdout: output, stderr: ""),
            suitePath: "/probe",
        )

        #expect(message.contains("(buildFailed)"))
        #expect(message.contains("cannot find 'missing' in scope"))
        #expect(!message.contains("Building for production"))
    }

    @Test
    func `a failure the parse finds no diagnostic in keeps the raw tail`() {
        let output = """
            Building for production...
            error: benchmarkCrashed
            """
        let message = SwiftPackageBenchmarkTool.failureMessage(
            subcommand: .run, result: .init(exitCode: 1, stdout: output, stderr: ""),
            suitePath: "/probe",
        )

        #expect(message.contains("(benchmarkCrashed)"))
        #expect(message.contains("Building for production"))
    }
}
