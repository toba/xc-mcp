import System
import Foundation
import Subprocess

/// Wrapper for executing Swift commands.
///
/// `SwiftRunner` provides a Swift interface for invoking the Swift command-line
/// tools. It supports building, testing, and running Swift packages.
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

    /// Extended timeout for cold-cache builds where SwiftPM must resolve and
    /// compile dependencies from scratch (15 minutes). Heavy dependency graphs
    /// like swift-syntax can easily exceed `defaultTimeout` on a first build.
    public static let coldCacheTimeout: Duration = .seconds(900)

    /// Reads `XC_MCP_SWIFT_EXTRA_ARGS` from the environment and shell-tokenizes
    /// it into additional swift build/test arguments.
    ///
    /// Useful for opting into experimental SwiftPM/Swift compiler flags without
    /// changing tool call sites. Example:
    ///
    /// ```sh
    /// export XC_MCP_SWIFT_EXTRA_ARGS="-Xswiftc -experimental-skip-non-inlinable-function-bodies"
    /// ```
    ///
    /// Tokenization is whitespace-separated and does **not** support quoting —
    /// individual arguments must not contain spaces.
    public static func extraArgsFromEnvironment() -> [String] {
        guard let raw = ProcessInfo.processInfo.environment["XC_MCP_SWIFT_EXTRA_ARGS"],
              !raw.isEmpty
        else { return [] }
        return raw.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Returns true when the package's SwiftPM build cache is empty or missing.
    ///
    /// A "cold" cache means dependencies haven't been resolved/built yet, so the
    /// next `swift build` or `swift test` will need to fetch and compile the
    /// full dependency graph — which can take well beyond `defaultTimeout`.
    public static func isColdCache(packagePath: String) -> Bool {
        let fm = FileManager.default
        let buildDir = packagePath + "/.build"
        guard fm.fileExists(atPath: buildDir) else { return true }
        // A populated checkouts directory is the strongest signal that
        // dependency resolution has run at least once.
        let checkouts = buildDir + "/checkouts"
        if let entries = try? fm.contentsOfDirectory(atPath: checkouts), !entries.isEmpty {
            return false
        }
        return true
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
    /// - Returns: The result containing exit code and output.
    /// - Throws: ``ProcessError/timeout(duration:)`` if the command exceeds the timeout.
    public func run(
        arguments: [String],
        workingDirectory: String? = nil,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        var guardFD: Int32?
        if let workingDirectory {
            guardFD = try await BuildGuard.acquire(
                path: workingDirectory,
                description: "swift \(arguments.first ?? "")",
            )
        }
        do {
            let result = try await ProcessResult.runSubprocess(
                .path("/usr/bin/swift"),
                arguments: Arguments(arguments),
                workingDirectory: workingDirectory.map { FilePath($0) },
                environment: environment,
                timeout: timeout,
                onProgress: onProgress,
            )
            if let guardFD { BuildGuard.release(fd: guardFD) }
            return result
        } catch {
            if let guardFD { BuildGuard.release(fd: guardFD) }
            throw error
        }
    }

    /// Builds a Swift package.
    ///
    /// - Parameters:
    ///   - packagePath: Path to the Swift package directory.
    ///   - configuration: Build configuration ("debug" or "release"). Defaults to "debug".
    ///   - product: Optional specific product to build.
    ///   - buildTests: When true, also builds test targets.
    ///   - timeout: Maximum time to wait. Defaults to ``defaultTimeout``.
    /// - Returns: The build result containing exit code and output.
    public func build(
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil,
        buildTests: Bool = false,
        verbose: Bool = false,
        environment: Environment = .inherit,
        timeout: Duration = Self.defaultTimeout,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> SwiftResult {
        var args = ["build", "-c", configuration]
        if verbose {
            args.append("-v")
        }
        if let product {
            args.append(contentsOf: ["--product", product])
        }
        if buildTests {
            args.append("--build-tests")
        }
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
        if let filter {
            args.append(contentsOf: ["--filter", filter])
        }
        if let skip {
            args.append(contentsOf: ["--skip", skip])
        }
        if let parallel {
            args.append(parallel ? "--parallel" : "--no-parallel")
        }
        args.append(contentsOf: Self.extraArgsFromEnvironment())
        return try await run(
            arguments: args,
            workingDirectory: packagePath,
            environment: environment,
            timeout: timeout,
            onProgress: onProgress,
        )
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
        if let executableName {
            args.append(executableName)
        }
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
