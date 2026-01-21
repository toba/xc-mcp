import Foundation
import MCP

/// Manages active LLDB debug sessions.
///
/// Tracks which processes are currently being debugged by their bundle ID.
public actor LLDBSessionManager {
    /// Shared singleton instance.
    public static let shared = LLDBSessionManager()

    /// Active debug sessions mapping bundle ID to process ID.
    private var activeSessions: [String: Int32] = [:]

    /// Registers a new debug session.
    ///
    /// - Parameters:
    ///   - bundleId: The bundle identifier of the app being debugged.
    ///   - pid: The process ID of the debugged process.
    public func registerSession(bundleId: String, pid: Int32) {
        activeSessions[bundleId] = pid
    }

    /// Gets the process ID for an active debug session.
    ///
    /// - Parameter bundleId: The bundle identifier to look up.
    /// - Returns: The process ID if the session exists, nil otherwise.
    public func getSession(bundleId: String) -> Int32? {
        activeSessions[bundleId]
    }

    /// Removes a debug session.
    ///
    /// - Parameter bundleId: The bundle identifier of the session to remove.
    public func removeSession(bundleId: String) {
        activeSessions.removeValue(forKey: bundleId)
    }

    /// Gets all active debug sessions.
    ///
    /// - Returns: Dictionary mapping bundle IDs to process IDs.
    public func getAllSessions() -> [String: Int32] {
        activeSessions
    }
}

/// Wrapper for executing LLDB commands.
///
/// `LLDBRunner` provides a Swift interface for invoking the LLDB debugger.
/// It supports attaching to processes, setting breakpoints, and inspecting
/// program state.
///
/// ## Example
///
/// ```swift
/// let runner = LLDBRunner()
///
/// // Attach to a process
/// let result = try await runner.attachToPID(12345)
///
/// // Set a breakpoint
/// try await runner.setBreakpoint(pid: 12345, symbol: "viewDidLoad")
///
/// // Get stack trace
/// let stack = try await runner.getStack(pid: 12345)
/// ```
public struct LLDBRunner: Sendable {
    /// Creates a new LLDB runner.
    public init() {}

    /// Executes an LLDB command with the given arguments.
    ///
    /// - Parameter arguments: The command-line arguments to pass to lldb.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String]) async throws -> LLDBResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = LLDBResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Executes LLDB in batch mode with a script.
    ///
    /// - Parameter commands: An array of LLDB commands to execute.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the script cannot be written or the process fails.
    public func runBatch(commands: [String]) async throws -> LLDBResult {
        // Create a temporary script file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("lldb_script_\(UUID().uuidString).lldb")

        let script = commands.joined(separator: "\n")
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: scriptPath)
        }

        return try await run(arguments: ["-s", scriptPath.path, "--batch"])
    }

    /// Attaches to a process by its process ID.
    ///
    /// - Parameter pid: The process ID to attach to.
    /// - Returns: The result containing exit code and output.
    public func attachToPID(_ pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "process status",
        ])
    }

    /// Attaches to a process by name.
    ///
    /// - Parameter processName: The name of the process to attach to.
    /// - Returns: The result containing exit code and output.
    public func attachToProcess(_ processName: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --name \"\(processName)\"",
            "process status",
        ])
    }

    /// Detaches from a process.
    ///
    /// - Parameter pid: The process ID to detach from.
    /// - Returns: The result containing exit code and output.
    public func detach(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "detach",
        ])
    }

    /// Sets a breakpoint at a symbol (function name).
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - symbol: The symbol name to break on (e.g., function name).
    /// - Returns: The result containing exit code and output.
    public func setBreakpoint(pid: Int32, symbol: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint set --name \"\(symbol)\"",
            "breakpoint list",
            "detach",
        ])
    }

    /// Sets a breakpoint at a specific file and line number.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - file: The source file path.
    ///   - line: The line number in the source file.
    /// - Returns: The result containing exit code and output.
    public func setBreakpoint(pid: Int32, file: String, line: Int) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint set --file \"\(file)\" --line \(line)",
            "breakpoint list",
            "detach",
        ])
    }

    /// Lists all breakpoints in the target process.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing breakpoint information.
    public func listBreakpoints(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint list",
            "detach",
        ])
    }

    /// Deletes a breakpoint by its ID.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - breakpointId: The breakpoint ID to delete.
    /// - Returns: The result containing exit code and output.
    public func deleteBreakpoint(pid: Int32, breakpointId: Int) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint delete \(breakpointId)",
            "breakpoint list",
            "detach",
        ])
    }

    /// Continues execution of a stopped process.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing exit code and output.
    public func continueExecution(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "continue",
        ])
    }

    /// Gets the current stack trace.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - threadIndex: Optional thread index to get backtrace for (all threads if nil).
    /// - Returns: The result containing stack trace information.
    public func getStack(pid: Int32, threadIndex: Int? = nil) async throws -> LLDBResult {
        var commands = ["process attach --pid \(pid)"]
        if let threadIndex {
            commands.append("thread backtrace --thread \(threadIndex)")
        } else {
            commands.append("thread backtrace all")
        }
        commands.append("detach")
        return try await runBatch(commands: commands)
    }

    /// Gets variables in the current stack frame.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - frameIndex: The stack frame index to inspect (0 is current frame).
    /// - Returns: The result containing variable information.
    public func getVariables(pid: Int32, frameIndex: Int = 0) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "frame select \(frameIndex)",
            "frame variable",
            "detach",
        ])
    }

    /// Executes a custom LLDB command.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - command: The LLDB command to execute.
    /// - Returns: The result containing command output.
    public func executeCommand(pid: Int32, command: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            command,
            "detach",
        ])
    }
}

/// Errors that can occur during LLDB operations.
public enum LLDBError: LocalizedError, Sendable, MCPErrorConvertible {
    /// An LLDB command failed with an error message.
    case commandFailed(String)

    /// Failed to attach to a process.
    case attachFailed(String)

    /// No active debug session exists.
    case noActiveSession

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "LLDB command failed: \(message)"
        case .attachFailed(let message):
            return "Failed to attach to process: \(message)"
        case .noActiveSession:
            return "No active debug session"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
        case .noActiveSession:
            return .invalidParams(errorDescription ?? "No active debug session")
        case .commandFailed, .attachFailed:
            return .internalError(errorDescription ?? "Debug operation failed")
        }
    }
}
