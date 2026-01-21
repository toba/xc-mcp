import Foundation

/// Result of an LLDB command execution
public struct LLDBResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }

    public var output: String {
        if stderr.isEmpty {
            return stdout
        } else if stdout.isEmpty {
            return stderr
        } else {
            return stdout + "\n" + stderr
        }
    }
}

/// Manages LLDB debug sessions
public actor LLDBSessionManager {
    public static let shared = LLDBSessionManager()

    private var activeSessions: [String: Int32] = [:]  // bundleId -> pid

    public func registerSession(bundleId: String, pid: Int32) {
        activeSessions[bundleId] = pid
    }

    public func getSession(bundleId: String) -> Int32? {
        activeSessions[bundleId]
    }

    public func removeSession(bundleId: String) {
        activeSessions.removeValue(forKey: bundleId)
    }

    public func getAllSessions() -> [String: Int32] {
        activeSessions
    }
}

/// Wrapper for executing LLDB commands
public struct LLDBRunner: Sendable {
    public init() {}

    /// Execute an lldb command with the given arguments
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

    /// Execute lldb in batch mode with a script
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

    /// Attach to a process by PID
    public func attachToPID(_ pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "process status",
        ])
    }

    /// Attach to a process by name
    public func attachToProcess(_ processName: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --name \"\(processName)\"",
            "process status",
        ])
    }

    /// Detach from the current process
    public func detach(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "detach",
        ])
    }

    /// Set a breakpoint at a symbol
    public func setBreakpoint(pid: Int32, symbol: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint set --name \"\(symbol)\"",
            "breakpoint list",
            "detach",
        ])
    }

    /// Set a breakpoint at a file:line
    public func setBreakpoint(pid: Int32, file: String, line: Int) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint set --file \"\(file)\" --line \(line)",
            "breakpoint list",
            "detach",
        ])
    }

    /// List all breakpoints
    public func listBreakpoints(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint list",
            "detach",
        ])
    }

    /// Delete a breakpoint by ID
    public func deleteBreakpoint(pid: Int32, breakpointId: Int) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "breakpoint delete \(breakpointId)",
            "breakpoint list",
            "detach",
        ])
    }

    /// Continue execution
    public func continueExecution(pid: Int32) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "continue",
        ])
    }

    /// Get the current stack trace
    public func getStack(pid: Int32, threadIndex: Int? = nil) async throws -> LLDBResult {
        var commands = ["process attach --pid \(pid)"]
        if let threadIndex = threadIndex {
            commands.append("thread backtrace --thread \(threadIndex)")
        } else {
            commands.append("thread backtrace all")
        }
        commands.append("detach")
        return try await runBatch(commands: commands)
    }

    /// Get variables in current frame
    public func getVariables(pid: Int32, frameIndex: Int = 0) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            "frame select \(frameIndex)",
            "frame variable",
            "detach",
        ])
    }

    /// Execute a custom LLDB command
    public func executeCommand(pid: Int32, command: String) async throws -> LLDBResult {
        try await runBatch(commands: [
            "process attach --pid \(pid)",
            command,
            "detach",
        ])
    }
}

/// Errors that can occur during LLDB operations
public enum LLDBError: LocalizedError, Sendable {
    case commandFailed(String)
    case attachFailed(String)
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
}
