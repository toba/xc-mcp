import Foundation
import MCP

/// A persistent LLDB process that stays alive across tool calls.
///
/// Instead of spawning a new `lldb --batch` process for each command,
/// `LLDBSession` keeps a single LLDB process running and sends commands
/// via stdin, reading responses until the `(lldb) ` prompt reappears.
public actor LLDBSession {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderr: FileHandle
    private let commandTimeout: TimeInterval

    /// The PID of the process being debugged.
    public let targetPID: Int32

    /// Whether the LLDB process is still running.
    public var isAlive: Bool {
        process.isRunning
    }

    /// Creates a new persistent LLDB session attached to a process.
    ///
    /// - Parameters:
    ///   - pid: The process ID to debug.
    ///   - commandTimeout: Maximum time to wait for a command response (default 30s).
    /// - Throws: If LLDB fails to start or attach.
    public init(pid: Int32, commandTimeout: TimeInterval = 30) throws {
        self.targetPID = pid
        self.commandTimeout = commandTimeout

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")
        proc.arguments = ["--no-use-colors"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdout = stdoutPipe.fileHandleForReading
        self.stderr = stderrPipe.fileHandleForReading

        try proc.run()
    }

    /// Waits for the initial LLDB prompt, then attaches to the target process.
    ///
    /// Must be called exactly once after `init` before sending other commands.
    /// - Returns: The attach command output.
    @discardableResult
    public func attach() async throws -> String {
        // Wait for initial prompt
        _ = try await readUntilPrompt()
        // Attach to the target process
        return try await sendCommand("process attach --pid \(targetPID)")
    }

    /// Sends a command to the LLDB process and waits for the response.
    ///
    /// - Parameter command: The LLDB command to execute.
    /// - Returns: The output produced by the command.
    /// - Throws: ``LLDBError/commandFailed(_:)`` on timeout or if the process has exited.
    public func sendCommand(_ command: String) async throws -> String {
        guard process.isRunning else {
            throw LLDBError.commandFailed("LLDB process is no longer running")
        }

        let commandData = Data((command + "\n").utf8)
        try stdin.write(contentsOf: commandData)

        return try await readUntilPrompt()
    }

    /// Terminates the LLDB process.
    public func terminate() {
        if process.isRunning {
            // Try graceful quit first
            let quitData = Data("quit\n".utf8)
            try? stdin.write(contentsOf: quitData)

            // Give it a moment, then force kill
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    /// Reads output from LLDB until the `(lldb) ` prompt appears.
    private func readUntilPrompt() async throws -> String {
        let promptMarker = "(lldb) "
        var accumulated = ""

        return try await withCheckedThrowingContinuation { continuation in
            let workItem = DispatchWorkItem { [stdout] in
                var buffer = Data()
                while true {
                    let chunk = stdout.availableData
                    if chunk.isEmpty {
                        // EOF — process exited
                        continuation.resume(returning: accumulated)
                        return
                    }
                    buffer.append(chunk)
                    if let str = String(data: buffer, encoding: .utf8) {
                        buffer = Data()
                        accumulated += str
                        if accumulated.hasSuffix(promptMarker) {
                            // Strip the trailing prompt from the output
                            let endIndex = accumulated.index(
                                accumulated.endIndex, offsetBy: -promptMarker.count)
                            let result = String(accumulated[accumulated.startIndex..<endIndex])
                            continuation.resume(returning: result)
                            return
                        }
                    }
                }
            }

            // Timeout handling
            let timeoutItem = DispatchWorkItem {
                workItem.cancel()
                continuation.resume(
                    throwing: LLDBError.commandFailed(
                        "Timed out waiting for LLDB response"))
            }

            DispatchQueue.global().async(execute: workItem)
            DispatchQueue.global().asyncAfter(
                deadline: .now() + self.commandTimeout, execute: timeoutItem)

            // Cancel timeout if work completes first
            workItem.notify(queue: .global()) {
                timeoutItem.cancel()
            }
        }
    }
}

/// Manages active LLDB debug sessions.
///
/// Tracks persistent LLDB processes by PID and provides bundle ID lookup.
public actor LLDBSessionManager {
    /// Shared singleton instance.
    public static let shared = LLDBSessionManager()

    /// Active LLDB sessions keyed by target PID.
    private var sessions: [Int32: LLDBSession] = [:]

    /// Bundle ID to PID mapping for convenience lookup.
    private var bundleIdToPID: [String: Int32] = [:]

    /// Creates a new persistent LLDB session attached to a process.
    ///
    /// If a session already exists for this PID and is still alive, returns it.
    ///
    /// - Parameter pid: The process ID to debug.
    /// - Returns: The LLDB session.
    public func createSession(pid: Int32) async throws -> LLDBSession {
        if let existing = sessions[pid], await existing.isAlive {
            return existing
        }

        // Clean up any dead session for this PID
        sessions.removeValue(forKey: pid)

        let session = try LLDBSession(pid: pid)
        try await session.attach()
        sessions[pid] = session
        return session
    }

    /// Gets an existing session for a PID.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: The session if one exists and is alive, nil otherwise.
    public func getSession(pid: Int32) async -> LLDBSession? {
        guard let session = sessions[pid] else { return nil }
        if await session.isAlive {
            return session
        }
        // Clean up dead session
        sessions.removeValue(forKey: pid)
        return nil
    }

    /// Gets an existing session by bundle ID.
    ///
    /// - Parameter bundleId: The bundle identifier.
    /// - Returns: The PID and session if found, nil otherwise.
    public func getSession(bundleId: String) async -> (pid: Int32, session: LLDBSession)? {
        guard let pid = bundleIdToPID[bundleId] else { return nil }
        guard let session = await getSession(pid: pid) else {
            // Clean up stale mapping
            bundleIdToPID.removeValue(forKey: bundleId)
            return nil
        }
        return (pid, session)
    }

    /// Gets the PID for a bundle ID (for backward compatibility).
    ///
    /// - Parameter bundleId: The bundle identifier.
    /// - Returns: The process ID if a session exists, nil otherwise.
    public func getPID(bundleId: String) async -> Int32? {
        guard let result = await getSession(bundleId: bundleId) else { return nil }
        return result.pid
    }

    /// Associates a bundle ID with a PID.
    ///
    /// - Parameters:
    ///   - bundleId: The bundle identifier.
    ///   - pid: The process ID.
    public func registerBundleId(_ bundleId: String, forPID pid: Int32) {
        bundleIdToPID[bundleId] = pid
    }

    /// Removes and terminates a session by PID.
    ///
    /// - Parameter pid: The process ID.
    public func removeSession(pid: Int32) async {
        if let session = sessions.removeValue(forKey: pid) {
            await session.terminate()
        }
        // Clean up any bundle ID mappings that pointed to this PID
        bundleIdToPID = bundleIdToPID.filter { $0.value != pid }
    }

    /// Removes and terminates a session by bundle ID.
    ///
    /// - Parameter bundleId: The bundle identifier.
    public func removeSession(bundleId: String) async {
        guard let pid = bundleIdToPID.removeValue(forKey: bundleId) else { return }
        await removeSession(pid: pid)
    }

    /// Gets all active sessions as a bundle ID to PID mapping.
    ///
    /// - Returns: Dictionary mapping bundle IDs to process IDs.
    public func getAllSessions() -> [String: Int32] {
        bundleIdToPID
    }

    /// Gets or creates a session for a PID.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: An existing or new LLDB session.
    public func getOrCreateSession(pid: Int32) async throws -> LLDBSession {
        if let session = await getSession(pid: pid) {
            return session
        }
        return try await createSession(pid: pid)
    }
}

/// Wrapper for executing LLDB commands.
///
/// `LLDBRunner` provides a Swift interface for invoking the LLDB debugger.
/// It uses persistent LLDB sessions that stay alive across tool calls,
/// so breakpoints persist and repeated attach/detach cycles are avoided.
///
/// ## Example
///
/// ```swift
/// let runner = LLDBRunner()
///
/// // Attach to a process (creates persistent session)
/// let result = try await runner.attachToPID(12345)
///
/// // Set a breakpoint (reuses existing session)
/// try await runner.setBreakpoint(pid: 12345, symbol: "viewDidLoad")
///
/// // Get stack trace
/// let stack = try await runner.getStack(pid: 12345)
/// ```
public struct LLDBRunner: Sendable {
    /// Creates a new LLDB runner.
    public init() {}

    /// Attaches to a process by its process ID.
    ///
    /// Creates a persistent LLDB session that stays alive for subsequent commands.
    ///
    /// - Parameter pid: The process ID to attach to.
    /// - Returns: The result containing the attach output.
    public func attachToPID(_ pid: Int32) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.createSession(pid: pid)
        let statusOutput = try await session.sendCommand("process status")
        return LLDBResult(exitCode: 0, stdout: statusOutput, stderr: "")
    }

    /// Attaches to a process by name.
    ///
    /// - Parameter processName: The name of the process to attach to.
    /// - Returns: The result containing attach output.
    public func attachToProcess(_ processName: String) async throws -> LLDBResult {
        // For name-based attach, we need a temporary batch approach since
        // we don't know the PID upfront. Use the old batch method.
        return try await runBatch(commands: [
            "process attach --name \"\(processName)\"",
            "process status",
        ])
    }

    /// Detaches from a process and terminates the persistent session.
    ///
    /// - Parameter pid: The process ID to detach from.
    /// - Returns: The result containing the detach output.
    public func detach(pid: Int32) async throws -> LLDBResult {
        let session = await LLDBSessionManager.shared.getSession(pid: pid)
        if let session {
            let output = try await session.sendCommand("detach")
            await LLDBSessionManager.shared.removeSession(pid: pid)
            return LLDBResult(exitCode: 0, stdout: output, stderr: "")
        }
        // No existing session — nothing to detach from
        return LLDBResult(exitCode: 0, stdout: "No active session for PID \(pid)", stderr: "")
    }

    /// Sets a breakpoint at a symbol (function name).
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - symbol: The symbol name to break on (e.g., function name).
    /// - Returns: The result containing breakpoint information.
    public func setBreakpoint(pid: Int32, symbol: String) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let setOutput = try await session.sendCommand("breakpoint set --name \"\(symbol)\"")
        let listOutput = try await session.sendCommand("breakpoint list")
        return LLDBResult(
            exitCode: 0,
            stdout: setOutput + "\n" + listOutput,
            stderr: ""
        )
    }

    /// Sets a breakpoint at a specific file and line number.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - file: The source file path.
    ///   - line: The line number in the source file.
    /// - Returns: The result containing breakpoint information.
    public func setBreakpoint(pid: Int32, file: String, line: Int) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let setOutput = try await session.sendCommand(
            "breakpoint set --file \"\(file)\" --line \(line)")
        let listOutput = try await session.sendCommand("breakpoint list")
        return LLDBResult(
            exitCode: 0,
            stdout: setOutput + "\n" + listOutput,
            stderr: ""
        )
    }

    /// Lists all breakpoints in the target process.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing breakpoint information.
    public func listBreakpoints(pid: Int32) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand("breakpoint list")
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Deletes a breakpoint by its ID.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - breakpointId: The breakpoint ID to delete.
    /// - Returns: The result containing updated breakpoint list.
    public func deleteBreakpoint(pid: Int32, breakpointId: Int) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let deleteOutput = try await session.sendCommand("breakpoint delete \(breakpointId)")
        let listOutput = try await session.sendCommand("breakpoint list")
        return LLDBResult(
            exitCode: 0,
            stdout: deleteOutput + "\n" + listOutput,
            stderr: ""
        )
    }

    /// Continues execution of a stopped process.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing continue output.
    public func continueExecution(pid: Int32) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand("continue")
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Gets the current stack trace.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - threadIndex: Optional thread index to get backtrace for (all threads if nil).
    /// - Returns: The result containing stack trace information.
    public func getStack(pid: Int32, threadIndex: Int? = nil) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let command: String
        if let threadIndex {
            command = "thread backtrace --thread \(threadIndex)"
        } else {
            command = "thread backtrace all"
        }
        let output = try await session.sendCommand(command)
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Gets variables in the current stack frame.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - frameIndex: The stack frame index to inspect (0 is current frame).
    /// - Returns: The result containing variable information.
    public func getVariables(pid: Int32, frameIndex: Int = 0) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let selectOutput = try await session.sendCommand("frame select \(frameIndex)")
        let varsOutput = try await session.sendCommand("frame variable")
        return LLDBResult(
            exitCode: 0,
            stdout: selectOutput + "\n" + varsOutput,
            stderr: ""
        )
    }

    /// Executes a custom LLDB command.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - command: The LLDB command to execute.
    /// - Returns: The result containing command output.
    public func executeCommand(pid: Int32, command: String) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand(command)
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Evaluates an expression in the debugger context.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - expression: The expression to evaluate.
    ///   - language: Optional language (`"swift"` or `"objc"`).
    ///   - objectDescription: Whether to use `po` (default true).
    /// - Returns: The result containing expression output.
    public func evaluate(
        pid: Int32,
        expression: String,
        language: String?,
        objectDescription: Bool
    ) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let command: String
        if let language {
            command = "expr -l \(language) -- \(expression)"
        } else if objectDescription {
            command = "po \(expression)"
        } else {
            command = "expr \(expression)"
        }
        let output = try await session.sendCommand(command)
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Lists threads and optionally selects one.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - selectIndex: Optional thread index to switch to.
    /// - Returns: The result containing thread information.
    public func listThreads(pid: Int32, selectIndex: Int?) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let listOutput = try await session.sendCommand("thread list")
        if let selectIndex {
            let selectOutput = try await session.sendCommand("thread select \(selectIndex)")
            let infoOutput = try await session.sendCommand("thread info")
            return LLDBResult(
                exitCode: 0,
                stdout: listOutput + "\n" + selectOutput + "\n" + infoOutput,
                stderr: ""
            )
        }
        return LLDBResult(exitCode: 0, stdout: listOutput, stderr: "")
    }

    /// Manages watchpoints (add, remove, list).
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - action: The action to perform (`"add"`, `"remove"`, or `"list"`).
    ///   - variable: Variable name for add action.
    ///   - address: Memory address for add action (alternative to variable).
    ///   - watchpointId: Watchpoint ID for remove action.
    ///   - condition: Optional condition expression for add action.
    /// - Returns: The result containing watchpoint information.
    public func manageWatchpoint(
        pid: Int32,
        action: String,
        variable: String?,
        address: String?,
        watchpointId: Int?,
        condition: String?
    ) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        switch action {
        case "add":
            let setOutput: String
            if let variable {
                setOutput = try await session.sendCommand("watchpoint set variable \(variable)")
            } else if let address {
                setOutput = try await session.sendCommand("watchpoint set expression -- \(address)")
            } else {
                throw LLDBError.commandFailed("Either 'variable' or 'address' is required for add")
            }
            var output = setOutput
            if let condition {
                // Extract watchpoint ID from output to apply condition
                let modOutput = try await session.sendCommand(
                    "watchpoint modify -c '\(condition)'")
                output += "\n" + modOutput
            }
            let listOutput = try await session.sendCommand("watchpoint list")
            return LLDBResult(exitCode: 0, stdout: output + "\n" + listOutput, stderr: "")

        case "remove":
            guard let watchpointId else {
                throw LLDBError.commandFailed("watchpoint_id is required for remove")
            }
            let deleteOutput = try await session.sendCommand("watchpoint delete \(watchpointId)")
            let listOutput = try await session.sendCommand("watchpoint list")
            return LLDBResult(
                exitCode: 0,
                stdout: deleteOutput + "\n" + listOutput,
                stderr: ""
            )

        case "list":
            let output = try await session.sendCommand("watchpoint list")
            return LLDBResult(exitCode: 0, stdout: output, stderr: "")

        default:
            throw LLDBError.commandFailed("Unknown watchpoint action: \(action)")
        }
    }

    /// Steps through code execution.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - mode: Step mode (`"in"`, `"over"`, `"out"`, or `"instruction"`).
    /// - Returns: The result containing the new location after stepping.
    public func step(pid: Int32, mode: String) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let command: String
        switch mode {
        case "in": command = "thread step-in"
        case "over": command = "thread step-over"
        case "out": command = "thread step-out"
        case "instruction": command = "thread step-inst"
        default:
            throw LLDBError.commandFailed("Unknown step mode: \(mode)")
        }
        let stepOutput = try await session.sendCommand(command)
        let frameOutput = try await session.sendCommand("frame info")
        return LLDBResult(
            exitCode: 0,
            stdout: stepOutput + "\n" + frameOutput,
            stderr: ""
        )
    }

    /// Reads memory at an address.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - address: The memory address to read (hex string).
    ///   - count: Number of items to read.
    ///   - format: Output format (`"hex"`, `"bytes"`, `"ascii"`, or `"instruction"`).
    ///   - size: Item size in bytes (1, 2, 4, or 8).
    /// - Returns: The result containing memory contents.
    public func readMemory(
        pid: Int32,
        address: String,
        count: Int,
        format: String,
        size: Int
    ) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let fmt: String
        switch format {
        case "hex": fmt = "x"
        case "bytes": fmt = "Y"
        case "ascii": fmt = "c"
        case "instruction": fmt = "i"
        default: fmt = "x"
        }
        let output = try await session.sendCommand(
            "memory read --size \(size) --format \(fmt) --count \(count) \(address)")
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Looks up symbols, addresses, and types.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - address: Address to symbolicate.
    ///   - name: Symbol or function name regex.
    ///   - type: Type name to look up.
    ///   - verbose: Whether to use verbose output.
    /// - Returns: The result containing symbol information.
    public func symbolLookup(
        pid: Int32,
        address: String?,
        name: String?,
        type: String?,
        verbose: Bool
    ) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        var outputs: [String] = []

        if let address {
            let verboseFlag = verbose ? " -v" : ""
            let output = try await session.sendCommand(
                "image lookup --address \(address)\(verboseFlag)")
            outputs.append(output)
        }

        if let name {
            let output = try await session.sendCommand("image lookup -r -n \(name)")
            outputs.append(output)
        }

        if let type {
            let output = try await session.sendCommand("image lookup --type \(type)")
            outputs.append(output)
        }

        return LLDBResult(exitCode: 0, stdout: outputs.joined(separator: "\n"), stderr: "")
    }

    /// Dumps the UI view hierarchy.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - platform: `"ios"` or `"macos"`.
    ///   - address: Optional specific view address to inspect.
    ///   - constraints: Whether to show Auto Layout constraints.
    /// - Returns: The result containing the view hierarchy.
    public func viewHierarchy(
        pid: Int32,
        platform: String,
        address: String?,
        constraints: Bool
    ) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        var outputs: [String] = []

        if let address {
            let output = try await session.sendCommand(
                "expr -l objc -O -- [(id)\(address) recursiveDescription]")
            outputs.append(output)
            if constraints {
                let hOutput = try await session.sendCommand(
                    "expr -l objc -O -- [(id)\(address) constraintsAffectingLayoutForAxis:0]")
                let vOutput = try await session.sendCommand(
                    "expr -l objc -O -- [(id)\(address) constraintsAffectingLayoutForAxis:1]")
                outputs.append("Horizontal constraints:\n" + hOutput)
                outputs.append("Vertical constraints:\n" + vOutput)
            }
        } else if platform == "macos" {
            let output = try await session.sendCommand(
                "expr -l objc -O -- [[[NSApplication sharedApplication] mainWindow] contentView]._subtreeDescription"
            )
            outputs.append(output)
        } else {
            let output = try await session.sendCommand(
                "expr -l objc -O -- [[[UIApplication sharedApplication] keyWindow] recursiveDescription]"
            )
            outputs.append(output)
        }

        return LLDBResult(exitCode: 0, stdout: outputs.joined(separator: "\n\n"), stderr: "")
    }

    /// Gets the current process status.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing process state information.
    public func processStatus(pid: Int32) async throws -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand("process status")
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Executes LLDB in batch mode with a script (used for cases where persistent sessions aren't applicable).
    private func runBatch(commands: [String]) async throws -> LLDBResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")

            let tempDir = FileManager.default.temporaryDirectory
            let scriptPath = tempDir.appendingPathComponent(
                "lldb_script_\(UUID().uuidString).lldb")

            do {
                let script = commands.joined(separator: "\n")
                try script.write(to: scriptPath, atomically: true, encoding: .utf8)

                process.arguments = ["-s", scriptPath.path, "--batch"]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                try process.run()
                process.waitUntilExit()

                try? FileManager.default.removeItem(at: scriptPath)

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
                try? FileManager.default.removeItem(at: scriptPath)
                continuation.resume(throwing: error)
            }
        }
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
