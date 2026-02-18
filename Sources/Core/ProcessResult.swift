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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-n", "\(count)", path]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return output
            }
        } catch {}
        return nil
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
