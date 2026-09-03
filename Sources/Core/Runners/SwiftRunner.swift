import System
import Foundation
import Subprocess

/// Wrapper for executing Swift commands.
///
/// `SwiftRunner` provides a Swift interface for invoking the Swift command-line tools. It supports
/// building, testing, and running Swift packages.
///
/// ## Example
///
/// ```swift
/// let runner = SwiftRunner()
///
/// // Build a package
/// let result = try await runner.build(
///     packagePath: "/path/to/package",
///     configuration: "debug"
/// )
///
/// // Run tests
/// try await runner.test(packagePath: "/path/to/package")
/// ```
public struct SwiftRunner: Sendable {
    /// Default timeout for Swift commands (5 minutes).
    public static let defaultTimeout: Duration = .seconds(300)

    /// Extended timeout for cold-cache builds where SwiftPM must resolve and compile dependencies
    /// from scratch (15 minutes). Heavy dependency graphs like swift-syntax can easily exceed
    /// `defaultTimeout` on a first build.
    public static let coldCacheTimeout: Duration = .seconds(900)

    /// Reads `XC_MCP_SWIFT_EXTRA_ARGS` from the environment and shell-tokenizes it into additional
    /// swift build/test arguments.
    ///
    /// Useful for opting into experimental SwiftPM/Swift compiler flags without changing tool call
    /// sites. Example:
    ///
    /// ```sh
    /// export XC_MCP_SWIFT_EXTRA_ARGS="-Xswiftc -experimental-skip-non-inlinable-function-bodies"
    /// ```
    ///
    /// Tokenization is whitespace-separated and does **not** support quoting — individual arguments
    /// must not contain spaces.
    public static func extraArgsFromEnvironment() -> [String] {
        guard let raw = ProcessInfo.processInfo.environment["XC_MCP_SWIFT_EXTRA_ARGS"],
            !raw.isEmpty else { return [] }
        return raw.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Returns true when the package's SwiftPM build cache is empty or missing.
    ///
    /// A "cold" cache means dependencies haven't been resolved/built yet, so the next `swift build`
    /// or `swift test` will need to fetch and compile the full dependency graph — which can take
    /// well beyond `defaultTimeout`.
    public static func isColdCache(packagePath: String) -> Bool {
        let fm = FileManager.default
        let buildDir = packagePath + "/.build"
        guard fm.fileExists(atPath: buildDir) else { return true }
        // A populated checkouts directory is the strongest signal that dependency resolution has
        // run at least once.
        let checkouts = buildDir + "/checkouts"

        if let entries = try? fm.contentsOfDirectory(atPath: checkouts), !entries.isEmpty {
            return false
        }
        return true
    }

    /// Returns true when the next build must compile the whole dependency graph.
    ///
    /// A cross-compile writes into its own `.build/<triple>` tree, so a warm host cache buys it
    /// nothing. Any non-host destination therefore counts as cold. A release build writes into
    /// `.build/release`, which a warm debug cache leaves empty, so a first release build counts as
    /// cold as well.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - destination: The destination the caller asked for.
    ///   - configuration: The build configuration the caller asked for.
    public static func isColdCache(
        packagePath: String,
        destination: SwiftBuildDestination,
        configuration: String = "debug",
    ) -> Bool {
        guard destination.isHost, !isColdCache(packagePath: packagePath) else { return true }
        return !FileManager.default.fileExists(atPath: "\(packagePath)/.build/\(configuration)")
    }

    /// Builds the error text for a `swift` command that exceeded its deadline.
    ///
    /// - Parameters:
    ///   - command: The command that timed out, such as `swift build`.
    ///   - duration: The deadline the command exceeded.
    ///   - packagePath: Path to the Swift package directory.
    ///   - destination: The resolved destination, or `nil` for the host.
    ///   - usedColdCacheTimeout: True when the tool picked ``coldCacheTimeout`` on its own.
    ///   - advice: The closing sentence telling the caller what to do next.
    public static func timeoutMessage(
        command: String,
        duration: Duration,
        packagePath: String,
        destination: ResolvedSwiftDestination?,
        usedColdCacheTimeout: Bool,
        advice: String,
    ) -> String {
        let label = SwiftBuildDestination.label(for: destination)
        var message = "\(command) timed out after \(duration) (package: \(packagePath), \(label))."

        if usedColdCacheTimeout {
            let reason = destination == nil
                ? "Detected a cold SwiftPM cache"
                : "A cross-compile builds the whole dependency graph again"
            message += " \(reason); the cold-cache timeout (\(coldCacheTimeout)) was used."
        }
        message +=
            " Heavy dependency graphs (e.g. swift-syntax) can take longer than the default on a first build. \(advice)"
        return message
    }

    /// Creates a new Swift runner.
    public init() {}

    /// Executes a swift command with the given arguments.
    ///
    /// - Parameters:
    ///   - arguments: The command-line arguments to pass to swift.
    ///   - workingDirectory: Optional working directory for the command.
    ///   - environment: Environment variables for the subprocess. Defaults to `.inherit`.
    ///   - timeout: Maximum time to wait for the command. Defaults to ``defaultTimeout``.
    ///   - settle: Optional policy that bounds the wait after the command finishes its work.
    ///   - guarded: Whether to take the build lock for `workingDirectory`. Pass false when the
    ///     caller already holds it. A second acquire opens a second file descriptor, and `flock`
    ///     blocks a second open file description in the same process, so a nested call deadlocks.
    /// - Returns: The result containing exit code and output.
    /// - Throws: ``ProcessError/timeout(duration:)`` if the command exceeds the timeout.
    public func run(
        arguments: [String],
        workingDirectory: String? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        settle: CompletionSettle? = nil,
        guarded: Bool = true,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        try await BuildGuard.withGuard(
            path: guarded ? workingDirectory : nil,
            description: "swift \(arguments.first ?? "")",
        ) {
            try await ProcessResult.runSubprocess(
                .path("/usr/bin/swift"),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.map { FilePath($0) },
                environment: environment,
                timeout: timeout,
                settle: settle,
                onProgress: onProgress,
            )
        }
    }

    /// The arguments that make a build's modules importable with `@testable`.
    ///
    /// SwiftPM passes `-enable-testing` to a debug build alone. A release build of the test targets
    /// then fails every `@testable import` with "module 'X' was not compiled for testing", so a
    /// release run has to ask for testability explicitly.
    ///
    /// - Parameter configuration: The build configuration the caller asked for.
    /// - Returns: The extra arguments, empty for a debug build.
    public static func testabilityArguments(configuration: String) -> [String] {
        configuration == "debug" ? [] : ["-Xswiftc", "-enable-testing"]
    }

    /// The arguments that make one build report every file it can compile.
    ///
    /// The driver stops scheduling work once a compile job fails, so a build reports the first
    /// failing batch and nothing behind it. A refactor that breaks twenty files then costs twenty
    /// builds, and each one exists to learn the next file name.
    ///
    /// `-continue-building-after-errors` is a hidden `swiftc` option, listed by
    /// `swiftc -help-hidden`. It keeps the remaining jobs running, so one build names every broken
    /// file.
    public static let continueAfterErrorsArguments = [
        "-Xswiftc", "-continue-building-after-errors",
    ]

    /// Expands caller-supplied compiler flags into the `-Xswiftc` pairs SwiftPM expects.
    ///
    /// A caller writes the flag as `swiftc` spells it, such as `-Xllvm` followed by
    /// `-inline-threshold=0`, and each element gets its own `-Xswiftc`.
    ///
    /// - Parameter flags: The flags to forward to the compiler.
    /// - Returns: The expanded argument list.
    public static func swiftcArguments(_ flags: [String]) -> [String] {
        flags.flatMap { ["-Xswiftc", $0] }
    }

    /// Builds the `swift build` argument list.
    ///
    /// - Parameters:
    ///   - configuration: Build configuration ("debug" or "release").
    ///   - product: Optional specific product to build.
    ///   - buildTests: When true, also builds test targets.
    ///   - verbose: When true, asks the driver to print each subprocess invocation.
    ///   - saveTemps: When true, keeps the driver's temporary file lists so a crashed frontend
    ///     invocation can be replayed against them.
    ///   - destination: A resolved cross-compilation destination, or `nil` for the host.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    ///   - continueAfterErrors: When true, the compiler reports every file it can rather than the
    ///     first batch that fails. See ``continueAfterErrorsArguments``.
    /// - Returns: The argument list, `swift` itself excluded.
    public static func buildArguments(
        configuration: String = "debug",
        product: String? = nil,
        buildTests: Bool = false,
        verbose: Bool = false,
        saveTemps: Bool = false,
        destination: ResolvedSwiftDestination? = nil,
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        continueAfterErrors: Bool = true,
    ) -> [String] {
        var args = ["build", "-c", configuration]
        if verbose { args.append("-v") }
        if let product { args.append(contentsOf: ["--product", product]) }

        if buildTests {
            args.append("--build-tests")
            args.append(contentsOf: testabilityArguments(configuration: configuration))
        }
        args.append(contentsOf: destination?.arguments ?? [])
        args.append(contentsOf: traits.arguments)
        if saveTemps { args.append(contentsOf: ["-Xswiftc", "-save-temps"]) }
        if continueAfterErrors { args.append(contentsOf: continueAfterErrorsArguments) }
        args.append(contentsOf: swiftcArguments(swiftcFlags))
        args.append(contentsOf: extraArgsFromEnvironment())
        return args
    }

    /// Builds a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: Build configuration ("debug" or "release"). Defaults to "debug".
    ///   - product: Optional specific product to build.
    ///   - buildTests: When true, also builds test targets.
    ///   - destination: A resolved cross-compilation destination, or `nil` to build for the host.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    ///   - continueAfterErrors: When true, one build reports every file it can rather than the
    ///     first batch that fails.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    ///   - guarded: Whether to take the build lock for `packagePath`. Pass false when the caller
    ///     already holds it, because a nested acquire deadlocks.
    /// - Returns: The build result containing exit code and output.
    public func build(
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil,
        buildTests: Bool = false,
        verbose: Bool = false,
        saveTemps: Bool = false,
        destination: ResolvedSwiftDestination? = nil,
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        continueAfterErrors: Bool = true,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        guarded: Bool = true,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        let result = try await run(
            arguments: Self.buildArguments(
                configuration: configuration, product: product, buildTests: buildTests,
                verbose: verbose, saveTemps: saveTemps, destination: destination,
                traits: traits, swiftcFlags: swiftcFlags,
                continueAfterErrors: continueAfterErrors,
            ),
            workingDirectory: packagePath,
            environment: environment, timeout: timeout,
            guarded: guarded,
            onProgress: onProgress,
        )
        RawBuildLog.store(
            rawOutput: result.output,
            action: buildTests ? "swift build --build-tests" : "swift build",
            destination: SwiftBuildDestination.label(for: destination),
            succeeded: result.succeeded,
        )
        return result
    }

    /// Reruns a build that crashed the compiler, then reports what the rerun recovered.
    ///
    /// The rerun adds `-v` for the driver's own invocation, `-save-temps` so the driver keeps the
    /// file lists the crashed frontend job reads, and a `TMPDIR` under the crash directory so those
    /// file lists sit next to the replay script instead of in a directory the driver empties. The
    /// report names the replay script, the untruncated argv, and the crashing thread the OS wrote
    /// to `~/Library/Logs/DiagnosticReports`.
    ///
    /// - Parameters:
    ///   - signal: The signal the compiler died on.
    ///   - firstAttemptOutput: Output of the build that crashed, used when the rerun compiles
    ///     clean.
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: The configuration the crashed build used.
    ///   - product: The product the crashed build used.
    ///   - buildTests: Whether the crashed build included the test targets.
    ///   - destination: The destination the crashed build used.
    ///   - traits: The traits the crashed build used.
    ///   - swiftcFlags: The compiler flags the crashed build used.
    ///   - environment: Environment variables for the rerun, `TMPDIR` excepted.
    ///   - timeout: Maximum time to wait for the rerun.
    /// - Returns: The crash report, always non-empty.
    public func diagnoseCompilerCrash(
        signal: Int,
        firstAttemptOutput: String,
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil,
        buildTests: Bool = false,
        destination: ResolvedSwiftDestination? = nil,
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> String {
        let directory = CompilerCrashReport.defaultDirectory()
        let temporaries = directory.appendingPathComponent("driver-temps")
        try? FileManager.default.createDirectory(at: temporaries, withIntermediateDirectories: true)

        let verbose = try await build(
            packagePath: packagePath,
            configuration: configuration,
            product: product,
            buildTests: buildTests,
            verbose: true,
            saveTemps: true,
            destination: destination,
            traits: traits,
            swiftcFlags: swiftcFlags,
            environment: environment.updating(["TMPDIR": temporaries.path]),
            timeout: timeout,
        )

        var sections = [ErrorExtractor.extractCrashDetails(from: verbose.output, signal: signal)]

        // The rerun is the better source, because it ran with the temporaries preserved. A rerun
        // that compiles clean (a nondeterministic crash) still leaves the first attempt's argv.
        // Extracting once matters: a verbose release log runs to tens of megabytes.
        let argv = ErrorExtractor.extractFrontendArguments(from: verbose.output)
            ?? ErrorExtractor.extractFrontendArguments(from: firstAttemptOutput)
        let report = CompilerCrashReport.write(signal: signal, argv: argv, into: directory)
            .formatted()
        if !report.isEmpty { sections.append(report) }

        return sections.joined(separator: "\n\n")
    }

    /// Builds the `swift test` argument list.
    ///
    /// - Parameters:
    ///   - configuration: Build configuration ("debug" or "release").
    ///   - filter: Optional test filter pattern (include).
    ///   - skip: Optional test filter pattern (exclude).
    ///   - parallel: When non-nil, controls test parallelism.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    /// - Returns: The argument list, `swift` itself excluded.
    public static func testArguments(
        configuration: String = "debug",
        filter: String? = nil,
        skip: String? = nil,
        parallel: Bool? = nil,
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
    ) -> [String] {
        var args = ["test", "-c", configuration]
        if let filter { args.append(contentsOf: ["--filter", filter]) }
        if let skip { args.append(contentsOf: ["--skip", skip]) }
        if let parallel { args.append(parallel ? "--parallel" : "--no-parallel") }
        args.append(contentsOf: traits.arguments)
        args.append(contentsOf: testabilityArguments(configuration: configuration))
        args.append(contentsOf: swiftcArguments(swiftcFlags))
        args.append(contentsOf: extraArgsFromEnvironment())
        return args
    }

    /// Runs tests for a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: Build configuration ("debug" or "release"). Defaults to "debug".
    ///   - filter: Optional test filter pattern (include).
    ///   - skip: Optional test filter pattern (exclude).
    ///   - parallel: When non-nil, controls test parallelism.
    ///   - traits: The package traits to enable.
    ///   - swiftcFlags: Flags to forward to the compiler.
    ///   - environment: Environment variables for the subprocess. Defaults to `.inherit`.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The test result containing exit code and output.
    public func test(
        packagePath: String,
        configuration: String = "debug",
        filter: String? = nil,
        skip: String? = nil,
        parallel: Bool? = nil,
        traits: SwiftBuildTraits = .packageDefault,
        swiftcFlags: [String] = [],
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        let result = try await run(
            arguments: Self.testArguments(
                configuration: configuration, filter: filter, skip: skip, parallel: parallel,
                traits: traits, swiftcFlags: swiftcFlags,
            ),
            workingDirectory: packagePath,
            environment: environment,
            timeout: timeout,
            settle: Self.testSettle,
            onProgress: onProgress,
        )
        RawBuildLog.store(
            rawOutput: result.output,
            action: "swift test",
            destination: SwiftBuildDestination.hostLabel,
            succeeded: result.succeeded,
        )
        return result
    }

    /// Bounds the wait after `swift test` prints the summary of a whole run.
    ///
    /// `swift-test` reads the test binary's output pipe. A process the tests spawned that inherited
    /// that pipe and outlived them holds it open, so `swift-test` sits idle for minutes after the
    /// results are complete. (74fa1d59)
    ///
    /// Two signals guard a healthy run. The marker matches the root-suite summary alone, so a suite
    /// that finishes mid-run does not arm the watchdog. The watchdog then reads the process group's
    /// CPU time, so a run that goes quiet behind a 16 KB stdio buffer keeps its grace period.
    /// (b5f682b1)
    public static let testSettle = CompletionSettle(grace: .seconds(20)) { tail in
        ErrorExtractor.indicatesTestRunFinished(tail)
    }

    /// Runs a Swift package executable.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - executableName: Optional name of the executable to run.
    ///   - arguments: Arguments to pass to the executable.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The run result containing exit code and output.
    public func runExecutable(
        packagePath: String,
        executableName: String? = nil,
        arguments: [String] = [],
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> SwiftResult {
        var args = ["run"]
        if let executableName { args.append(executableName) }

        if !arguments.isEmpty {
            args.append("--")
            args.append(contentsOf: arguments)
        }
        return try await run(
            arguments: args, workingDirectory: packagePath,
            environment: environment, timeout: timeout,
        )
    }

    /// Cleans build artifacts for a Swift package.
    ///
    /// - Parameter packagePath: Path to the Swift package directory.
    /// - Returns: The clean result containing exit code and output.
    public func clean(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "clean"], workingDirectory: packagePath)
    }

    /// Emits a symbol graph for every target in a Swift package.
    ///
    /// SwiftPM writes the files into `.build/<triple>/symbolgraph` and prints that directory on the
    /// last line of stdout. The command builds the package first.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - minimumAccessLevel: Lowest access level to include: `private`, `fileprivate`,
    ///     `internal`, `package`, `public`, or `open`.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    ///   - onProgress: Optional callback for streamed output.
    /// - Returns: The command result containing exit code and output.
    public func dumpSymbolGraph(
        packagePath: String,
        minimumAccessLevel: String = "public",
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        try await run(
            arguments: [
                "package", "dump-symbol-graph",
                "--minimum-access-level", minimumAccessLevel,
            ],
            workingDirectory: packagePath,
            timeout: timeout,
            onProgress: onProgress,
        )
    }

    /// Dumps the package manifest as JSON.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The result whose stdout holds the manifest JSON.
    public func dumpPackage(
        packagePath: String,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> SwiftResult {
        try await run(
            arguments: ["package", "dump-package"],
            workingDirectory: packagePath,
            timeout: timeout,
        )
    }

    /// Shows package dependencies.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The result containing dependency tree.
    public func showDependencies(
        packagePath: String,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> SwiftResult {
        try await run(
            arguments: ["package", "show-dependencies"],
            workingDirectory: packagePath,
            timeout: timeout,
        )
    }

    /// Resolves package dependencies.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The resolve result containing exit code and output.
    public func resolve(
        packagePath: String,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> SwiftResult {
        try await run(
            arguments: ["package", "resolve"],
            workingDirectory: packagePath,
            timeout: timeout,
        )
    }

    /// Updates package dependencies to their latest versions.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The update result containing exit code and output.
    public func update(
        packagePath: String,
        timeout: Duration = Self.defaultTimeout,
    ) async throws -> SwiftResult {
        try await run(
            arguments: ["package", "update"],
            workingDirectory: packagePath,
            timeout: timeout,
        )
    }
}
