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
    /// nothing. Any non-host destination therefore counts as cold.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - destination: The destination the caller asked for.
    public static func isColdCache(
        packagePath: String,
        destination: SwiftBuildDestination,
    ) -> Bool {
        !destination.isHost || isColdCache(packagePath: packagePath)
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
    /// - Returns: The result containing exit code and output.
    /// - Throws: ``ProcessError/timeout(duration:)`` if the command exceeds the timeout.
    public func run(
        arguments: [String],
        workingDirectory: String? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        settle: CompletionSettle? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        try await BuildGuard.withGuard(
            path: workingDirectory,
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

    /// Builds a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: Build configuration ("debug" or "release"). Defaults to "debug".
    ///   - product: Optional specific product to build.
    ///   - buildTests: When true, also builds test targets.
    ///   - destination: A resolved cross-compilation destination, or `nil` to build for the host.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The build result containing exit code and output.
    public func build(
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil,
        buildTests: Bool = false,
        verbose: Bool = false,
        destination: ResolvedSwiftDestination? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        var args = ["build", "-c", configuration]
        if verbose { args.append("-v") }
        if let product { args.append(contentsOf: ["--product", product]) }
        if buildTests { args.append("--build-tests") }
        args.append(contentsOf: destination?.arguments ?? [])
        args.append(contentsOf: Self.extraArgsFromEnvironment())
        return try await run(
            arguments: args, workingDirectory: packagePath,
            environment: environment, timeout: timeout,
            onProgress: onProgress,
        )
    }

    /// Runs tests for a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - filter: Optional test filter pattern (include).
    ///   - skip: Optional test filter pattern (exclude).
    ///   - parallel: When non-nil, controls test parallelism.
    ///   - environment: Environment variables for the subprocess. Defaults to `.inherit`.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The test result containing exit code and output.
    public func test(
        packagePath: String,
        filter: String? = nil,
        skip: String? = nil,
        parallel: Bool? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        var args = ["test"]
        if let filter { args.append(contentsOf: ["--filter", filter]) }
        if let skip { args.append(contentsOf: ["--skip", skip]) }
        if let parallel { args.append(parallel ? "--parallel" : "--no-parallel") }
        args.append(contentsOf: Self.extraArgsFromEnvironment())
        return try await run(
            arguments: args,
            workingDirectory: packagePath,
            environment: environment,
            timeout: timeout,
            settle: Self.testSettle,
            onProgress: onProgress,
        )
    }

    /// Bounds the wait after `swift test` prints its summary.
    ///
    /// `swift-test` reads the test binary's output pipe. A process the tests spawned that inherited
    /// that pipe and outlived them holds it open, so `swift-test` sits idle for minutes after the
    /// results are complete. The grace period is long enough that no healthy run reaches it: a test
    /// binary prints its summary immediately before it exits, and any further SwiftPM output
    /// restarts the clock. (74fa1d59)
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
