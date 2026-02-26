import MCP
import System
import Foundation
import Subprocess

/// Errors that can occur during process execution.
public enum ProcessError: Error, Sendable, LocalizedError, MCPErrorConvertible {
    /// The process exceeded the allowed time limit.
    case timeout(duration: Duration)

    public var errorDescription: String? {
        switch self {
            case let .timeout(duration):
                return "Process timed out after \(duration)"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case let .timeout(duration):
                return .internalError("Process timed out after \(duration)")
        }
    }
}

/// Unified result of a process execution.
///
/// Contains the exit code and captured output from running any command-line process.
/// Used as the common result type for all runner utilities.
public struct ProcessResult: Sendable {
    /// The process exit code (0 indicates success).
    public let exitCode: Int32

    /// Standard output captured from the process.
    public let stdout: String

    /// Standard error captured from the process.
    public let stderr: String

    /// Creates a new process result.
    ///
    /// - Parameters:
    ///   - exitCode: The process exit code (0 indicates success).
    ///   - stdout: Standard output captured from the process.
    ///   - stderr: Standard error captured from the process.
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    /// Whether the command completed successfully (exit code 0).
    public var succeeded: Bool {
        exitCode == 0
    }

    /// Combined output from stdout and stderr.
    public var output: String {
        if stderr.isEmpty {
            return stdout
        } else if stdout.isEmpty {
            return stderr
        } else {
            return stdout + "\n" + stderr
        }
    }

    /// The most relevant error output: stderr if available, otherwise stdout.
    public var errorOutput: String {
        stderr.isEmpty ? stdout : stderr
    }
}

// MARK: - Run

extension ProcessResult {
    /// Runs a command asynchronously and captures its output.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable (e.g. "/usr/bin/open").
    ///   - arguments: Command-line arguments.
    ///   - mergeStderr: When true, stderr is merged into stdout (like `2>&1`).
    ///                  When false, stdout and stderr are captured separately.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func run(
        _ executablePath: String,
        arguments: [String] = [],
        mergeStderr: Bool = true,
        timeout: Duration? = nil,
    ) async throws -> ProcessResult {
        try await runSubprocess(
            .path(FilePath(executablePath)),
            arguments: Arguments(arguments),
            mergeStderr: mergeStderr,
            timeout: timeout,
        )
    }

    /// Runs a command asynchronously using Subprocess and captures its output.
    ///
    /// - Parameters:
    ///   - executable: The executable to run (e.g., `.name("xcrun")` or `.path("/usr/bin/swift")`).
    ///   - arguments: Command-line arguments.
    ///   - workingDirectory: Optional working directory for the command.
    ///   - mergeStderr: When true, stderr is merged into stdout (like `2>&1`).
    ///   - outputLimit: Maximum bytes to capture from stdout. Defaults to 10MB.
    ///   - errorLimit: Maximum bytes to capture from stderr. Defaults to 10MB.
    ///   - environment: Environment variables for the subprocess. Defaults to `.inherit`.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func runSubprocess(
        _ executable: Subprocess.Executable,
        arguments: Subprocess.Arguments = [],
        workingDirectory: FilePath? = nil,
        mergeStderr: Bool = false,
        outputLimit: Int = 10_485_760,
        errorLimit: Int = 10_485_760,
        environment: Environment = .inherit,
        timeout: Duration? = nil,
    ) async throws -> ProcessResult {
        if mergeStderr {
            let run: @Sendable () async throws -> CollectedResult<
                StringOutput<Unicode.UTF8>,
                CombinedErrorOutput,
            > = {
                try await Subprocess.run(
                    executable,
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    output: .string(limit: outputLimit),
                    error: .combineWithOutput,
                )
            }
            let result = try await raceTimeout(timeout, run: run)
            let exitCode: Int32 =
                switch result.terminationStatus {
                    case let .exited(code): code
                    case let .unhandledException(code): code
                }
            return ProcessResult(
                exitCode: exitCode,
                stdout: result.standardOutput ?? "",
                stderr: "",
            )
        } else {
            let run: @Sendable () async throws -> CollectedResult<
                StringOutput<Unicode.UTF8>,
                StringOutput<Unicode.UTF8>,
            > = {
                try await Subprocess.run(
                    executable,
                    arguments: arguments,
                    environment: environment,
                    workingDirectory: workingDirectory,
                    output: .string(limit: outputLimit),
                    error: .string(limit: errorLimit),
                )
            }
            let result = try await raceTimeout(timeout, run: run)
            let exitCode: Int32 =
                switch result.terminationStatus {
                    case let .exited(code): code
                    case let .unhandledException(code): code
                }
            return ProcessResult(
                exitCode: exitCode,
                stdout: result.standardOutput ?? "",
                stderr: result.standardError ?? "",
            )
        }
    }

    /// Races a subprocess closure against an optional timeout.
    ///
    /// When timeout is nil, runs the closure directly. When set, uses a task group
    /// to race the subprocess against a sleep, throwing ``ProcessError/timeout(duration:)``
    /// if the deadline is exceeded.
    private static func raceTimeout<T: Sendable>(
        _ timeout: Duration?,
        run: @escaping @Sendable () async throws -> T,
    ) async throws -> T {
        guard let timeout else {
            return try await run()
        }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await run()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ProcessError.timeout(duration: timeout)
            }
            guard let result = try await group.next() else {
                throw ProcessError.timeout(duration: timeout)
            }
            group.cancelAll()
            return result
        }
    }

    /// Discards the result. Useful for fire-and-forget commands like `kill` or `pkill`.
    @discardableResult
    public func ignore() -> ProcessResult {
        self
    }
}

// MARK: - Simctl Helpers

extension ProcessResult {
    /// Extracts a PID from simctl launch output (format: "bundle_id: 12345").
    public var launchedPID: String? {
        let components = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ": ")
        return components.count >= 2 ? components.last : nil
    }
}

// MARK: - File Utilities

public enum FileUtility {
    /// Reads the last N lines from a file using tail.
    public static func readTailLines(path: String, count: Int = 50) async -> String? {
        guard
            let result = try? await ProcessResult.run(
                "/usr/bin/tail", arguments: ["-n", "\(count)", path], mergeStderr: false,
            ),
            !result.stdout.isEmpty
        else {
            return nil
        }
        return result.stdout
    }
}

// MARK: - Log Capture Helpers

/// Shared helpers for log capture start/stop tools.
public enum LogCapture {
    /// Appends the tail of a log file to a message string.
    public static func appendTail(
        to message: inout String,
        from outputFile: String?,
        lines: Int,
    ) async {
        guard let outputFile,
              FileManager.default.fileExists(atPath: outputFile),
              let tailOutput = await FileUtility.readTailLines(path: outputFile, count: lines)
        else { return }

        message += "\n\nLast \(lines) lines of log:\n"
        message += String(repeating: "-", count: 50) + "\n"
        message += tailOutput
    }

    /// Opens or creates a file for writing log output and returns a `FileHandle` positioned at the end.
    ///
    /// - Parameter path: The file path to open for writing.
    /// - Returns: A `FileHandle` positioned at the end of the file.
    /// - Throws: ``MCPError/internalError(_:)`` if the file cannot be opened.
    public static func openOutputFile(at path: String) throws(MCPError) -> FileHandle {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: path) {
            fileManager.createFile(atPath: path, contents: nil)
        }
        guard let fileHandle = FileHandle(forWritingAtPath: path) else {
            throw .internalError("Failed to open output file: \(path)")
        }
        fileHandle.seekToEndOfFile()
        return fileHandle
    }

    /// Launches a streaming process that writes output to a file.
    ///
    /// - Parameters:
    ///   - executable: Path to the executable (e.g., "/usr/bin/xcrun", "/usr/bin/log").
    ///   - arguments: Command-line arguments.
    ///   - outputFile: Path to write output to.
    /// - Returns: The process identifier of the launched process.
    /// - Throws: ``MCPError`` if file opening or process launching fails.
    public static func launchStreamProcess(
        executable: String,
        arguments: [String],
        outputFile: String,
    ) throws(MCPError) -> Int32 {
        let fileHandle = try openOutputFile(at: outputFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = fileHandle
        process.standardError = fileHandle

        do {
            try process.run()
        } catch {
            throw .internalError("Failed to start log capture: \(error)")
        }

        return process.processIdentifier
    }

    /// Verifies that a log stream process is still running after launch.
    ///
    /// Waits briefly, then checks if the process has exited. If it exited with an error
    /// (e.g., invalid predicate syntax), reads the output file for error details and throws.
    ///
    /// - Parameters:
    ///   - pid: The process identifier returned by ``launchStreamProcess(executable:arguments:outputFile:)``.
    ///   - outputFile: Path to the log output file (may contain error output from the stream process).
    /// - Throws: ``MCPError/internalError(_:)`` if the process exited unexpectedly.
    public static func verifyStreamHealth(
        pid: Int32,
        outputFile: String,
    ) async throws(MCPError) {
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return // Cancelled — skip health check
        }

        // Check if the process is still running via kill(pid, 0)
        let running = kill(pid, 0) == 0
        guard !running else { return }

        // Process died — read output file for error details
        var detail = "Log stream process (PID \(pid)) exited immediately after launch."
        if let data = FileManager.default.contents(atPath: outputFile),
           let output = String(data: data, encoding: .utf8),
           !output.isEmpty
        {
            detail += "\nProcess output:\n\(output.prefix(500))"
        }
        throw .internalError(detail)
    }

    /// Stops a log capture process by PID or pattern-based kill.
    ///
    /// - Parameters:
    ///   - pid: Specific process ID to kill. If nil, uses pkill patterns.
    ///   - pkillPatterns: Patterns to pass to `pkill -f` as fallback.
    public static func stopCapture(pid: Int?, pkillPatterns: [String]) async {
        if let pid {
            _ = try? await ProcessResult.run("/bin/kill", arguments: ["\(pid)"])
        } else {
            for pattern in pkillPatterns {
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill", arguments: ["-f", pattern],
                )
            }
        }
    }
}

// MARK: - Type Aliases for Runner Compatibility

/// Result of an xcodebuild command execution.
public typealias XcodebuildResult = ProcessResult

/// Result of a simctl command execution.
public typealias SimctlResult = ProcessResult

/// Result of a devicectl command execution.
public typealias DeviceCtlResult = ProcessResult

/// Result of a Swift command execution.
public typealias SwiftResult = ProcessResult

/// Result of an LLDB command execution.
public typealias LLDBResult = ProcessResult
