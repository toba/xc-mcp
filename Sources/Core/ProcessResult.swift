import System
import Foundation
import Subprocess

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
    ) async throws -> ProcessResult {
        try await runSubprocess(
            .path(FilePath(executablePath)),
            arguments: Arguments(arguments),
            mergeStderr: mergeStderr,
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
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func runSubprocess(
        _ executable: Subprocess.Executable,
        arguments: Subprocess.Arguments = [],
        workingDirectory: FilePath? = nil,
        mergeStderr: Bool = false,
        outputLimit: Int = 10_485_760,
        errorLimit: Int = 10_485_760,
    ) async throws -> ProcessResult {
        if mergeStderr {
            let result = try await Subprocess.run(
                executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                output: .string(limit: outputLimit),
                error: .combineWithOutput,
            )
            let exitCode: Int32 = switch result.terminationStatus {
                case let .exited(code): code
                case let .unhandledException(code): code
            }
            return ProcessResult(
                exitCode: exitCode,
                stdout: result.standardOutput ?? "",
                stderr: "",
            )
        } else {
            let result = try await Subprocess.run(
                executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                output: .string(limit: outputLimit),
                error: .string(limit: errorLimit),
            )
            let exitCode: Int32 = switch result.terminationStatus {
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
