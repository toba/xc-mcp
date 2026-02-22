import Foundation

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

// MARK: - Pipe Reading

extension ProcessResult {
    /// Reads data from stdout and stderr pipes concurrently to avoid deadlock.
    ///
    /// When a process writes more than ~64KB to either pipe, it blocks until
    /// the pipe is drained. Reading both sequentially on the same thread
    /// deadlocks because `readDataToEndOfFile()` blocks until EOF.
    ///
    /// This method reads stderr on a background thread while reading stdout
    /// on the calling thread, then waits for both to complete.
    ///
    /// - Parameters:
    ///   - stdout: The pipe attached to the process's standard output.
    ///   - stderr: The pipe attached to the process's standard error, or nil if merged.
    /// - Returns: The captured data from both pipes.
    public static func drainPipes(
        stdout stdoutPipe: Pipe,
        stderr stderrPipe: Pipe?,
    ) -> (stdout: Data, stderr: Data) {
        nonisolated(unsafe) var capturedStderr = Data()
        let sem: DispatchSemaphore?
        if let stderrPipe {
            let s = DispatchSemaphore(value: 0)
            sem = s
            DispatchQueue.global().async {
                capturedStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                s.signal()
            }
        } else {
            sem = nil
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        sem?.wait()
        return (stdoutData, capturedStderr)
    }
}

// MARK: - Run

extension ProcessResult {
    /// Runs a command synchronously and captures its output.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable (e.g. "/usr/bin/open").
    ///   - arguments: Command-line arguments.
    ///   - mergeStderr: When true, stderr is piped to the same handle as stdout.
    ///                  When false, stdout and stderr are captured separately.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func run(
        _ executablePath: String,
        arguments: [String] = [],
        mergeStderr: Bool = true,
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe

        let stderrPipe: Pipe?
        if mergeStderr {
            process.standardError = stdoutPipe
            stderrPipe = nil
        } else {
            let pipe = Pipe()
            process.standardError = pipe
            stderrPipe = pipe
        }

        try process.run()

        let pipes = drainPipes(stdout: stdoutPipe, stderr: stderrPipe)
        process.waitUntilExit()

        let stdoutString = String(data: pipes.stdout, encoding: .utf8) ?? ""
        let stderrString = stderrPipe != nil
            ? (String(data: pipes.stderr, encoding: .utf8) ?? "")
            : ""

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutString,
            stderr: stderrString,
        )
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
    public static func readTailLines(path: String, count: Int = 50) -> String? {
        guard
            let result = try? ProcessResult.run(
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
    public static func appendTail(to message: inout String, from outputFile: String?, lines: Int) {
        guard let outputFile,
              FileManager.default.fileExists(atPath: outputFile),
              let tailOutput = FileUtility.readTailLines(path: outputFile, count: lines)
        else { return }

        message += "\n\nLast \(lines) lines of log:\n"
        message += String(repeating: "-", count: 50) + "\n"
        message += tailOutput
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
