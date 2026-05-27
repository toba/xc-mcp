import MCP
import Foundation
import Subprocess
import Synchronization

/// Thread-safe one-shot wrapper around a `CheckedContinuation` .
///
/// Ensures the continuation is resumed exactly once, even when multiple threads race to complete it
/// (e.g., a reader thread and a timeout handler).
private final class OneShotContinuation<T: Sendable>: Sendable {
    private let continuation: CheckedContinuation<T, any Error>
    private let resumed = Mutex(false)

    init(_ continuation: CheckedContinuation<T, any Error>) { self.continuation = continuation }

    /// Resumes with a value. Returns true if this call won the race.
    @discardableResult
    func resume(returning value: T) -> Bool {
        let didResume = resumed.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        if didResume { continuation.resume(returning: value) }
        return didResume
    }

    /// Resumes with an error. Returns true if this call won the race.
    @discardableResult
    func resume(throwing error: any Error) -> Bool {
        let didResume = resumed.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        if didResume { continuation.resume(throwing: error) }
        return didResume
    }
}

/// Opens a pseudo-TTY pair and returns (primary, replica) file descriptors.
///
/// LLDB suppresses the interactive `(lldb) ` prompt when stdin is a pipe. Using a PTY makes LLDB
/// believe it's connected to a terminal, so it emits prompts that `readUntilPrompt()` can detect.
private func openPTY() throws(LLDBError) -> (primary: Int32, replica: Int32) {
    let primary = posix_openpt(O_RDWR | O_NOCTTY)
    guard primary >= 0 else {
        throw LLDBError.commandFailed("posix_openpt failed: \(String(cString: strerror(errno)))")
    }
    guard grantpt(primary) == 0 else {
        close(primary)
        throw LLDBError.commandFailed("grantpt failed: \(String(cString: strerror(errno)))")
    }
    guard unlockpt(primary) == 0 else {
        close(primary)
        throw LLDBError.commandFailed("unlockpt failed: \(String(cString: strerror(errno)))")
    }
    guard let name = ptsname(primary) else {
        close(primary)
        throw LLDBError.commandFailed("ptsname failed: \(String(cString: strerror(errno)))")
    }
    let replica = open(name, O_RDWR | O_NOCTTY)
    guard replica >= 0 else {
        close(primary)
        throw LLDBError.commandFailed(
            "Failed to open replica PTY: \(String(cString: strerror(errno)))",
        )
    }

    // Disable echo and canonical mode on the replica so we don't get our own commands echoed back
    // through the PTY driver.
    var attrs = termios()
    tcgetattr(replica, &attrs)
    attrs.c_lflag &= ~UInt(ECHO | ICANON)
    tcsetattr(replica, TCSANOW, &attrs)

    return (primary, replica)
}

/// A persistent LLDB process that stays alive across tool calls.
///
/// Instead of spawning a new `lldb --batch` process for each command, `LLDBSession` keeps a single
/// LLDB process running and sends commands via stdin, reading responses until the `(lldb) ` prompt
/// reappears.
///
/// Uses a pseudo-TTY so LLDB emits interactive prompts. The state of the debugged process as
/// tracked by the LLDB session.
public enum ProcessState: Sendable, Equatable {
    /// State is not yet known.
    case unknown
    /// The process is running (after continue).
    case running
    /// The process is stopped (at a breakpoint, after a step, or due to a signal/crash).
    case stopped(reason: String?)

    /// Whether the process is in a stopped state (breakpoint, crash, step, etc.).
    public var isStopped: Bool {
        if case .stopped = self { return true }
        return false
    }

    /// Whether the process is stopped due to a crash signal (SIGABRT, SIGSEGV, etc.).
    public var isCrashed: Bool {
        guard case let .stopped(reason) = self else { return false }
        guard let reason else { return false }
        return reason.contains("signal SIG") || reason.contains("EXC_BAD_ACCESS")
            || reason.contains("EXC_CRASH")
    }
}

public actor LLDBSession {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let stderr: FileHandle
    /// Maximum time to wait for a command response. Mutable so the long launch/`--waitfor` window
    /// can be lowered to an interactive value once attach completes (see ``setCommandTimeout(_:)``).
    private var commandTimeout: TimeInterval
    /// File descriptors to close when the session is terminated.
    private let ptyFDs: [Int32]

    /// The PID of the process being debugged.
    public private(set) var targetPID: Int32

    /// Whether the session has been poisoned by a timeout and should be recreated.
    public private(set) var isPoisoned: Bool = false

    /// The last known state of the debugged process.
    public private(set) var processState: ProcessState = .unknown

    /// Whether the LLDB process is still running and the session is usable.
    public var isAlive: Bool { process.isRunning && !isPoisoned }

    /// Updates the target PID (e.g. after a `--waitfor` attach resolves).
    public func setTargetPID(_ pid: Int32) { targetPID = pid }

    /// Updates the tracked process state.
    public func setProcessState(_ state: ProcessState) { processState = state }

    /// The interactive per-command timeout used after launch/attach has completed.
    ///
    /// Launch/`--waitfor` sessions start with a long timeout so the initial attach can block on the
    /// target appearing; once the process is under debugger control, inspection commands
    /// (`thread backtrace`, `frame variable`, etc.) should fail fast rather than appear to hang for
    /// the full launch window. A wedged read then surfaces a structured timeout error and poisons
    /// the session in ~30s instead of two minutes.
    public static let interactiveCommandTimeout: TimeInterval = 30

    /// LLDB's own expression-evaluation timeout, in microseconds, applied to tool-built `expr`
    /// commands (view-hierarchy dumps, border toggles, `debug_evaluate`).
    ///
    /// AppKit/UIKit expression evaluation on an interrupted-at-an-arbitrary-point process can block
    /// far longer than the read-level ``interactiveCommandTimeout`` — e.g. `_subtreeDescription` on a
    /// macOS NSView tree (4ui-lsh). Passing `--timeout` makes LLDB itself abort the inferior call and
    /// return a clean `(lldb) ` prompt with a "timed out" diagnostic. The read then completes
    /// normally, so a slow dump fails the *single* call instead of wedging the PTY read and poisoning
    /// the shared session for every other debug tool. Kept comfortably below
    /// ``interactiveCommandTimeout`` so LLDB returns before the read-level timeout fires.
    public static let expressionTimeoutMicroseconds = 15_000_000

    /// The bounded-evaluation option string shared by all tool-built `expr` commands.
    ///
    /// `--timeout` caps the inferior call so a hung AppKit method returns control to LLDB; `--unwind-
    /// on-error true` and `--ignore-breakpoints true` keep a failed/timed-out evaluation from leaving
    /// the target parked mid-expression or tripping the user's breakpoints.
    static var exprTimeoutOptions: String {
        "--timeout \(expressionTimeoutMicroseconds) --unwind-on-error true --ignore-breakpoints true"
    }

    /// Builds an Objective-C `expr -O` (object-description) command with a bounded evaluation
    /// timeout. Options precede `--`, so the expression body is passed verbatim after it.
    static func objcExprCommand(_ body: String) -> String {
        "expr -l objc -O \(exprTimeoutOptions) -- \(body)"
    }

    /// Lowers (or raises) the per-command response timeout for subsequent commands.
    public func setCommandTimeout(_ timeout: TimeInterval) { commandTimeout = timeout }

    /// Creates a new persistent LLDB session attached to a process.
    ///
    /// Uses a pseudo-TTY for stdin/stdout so LLDB emits interactive prompts.
    ///
    /// - Parameters:
    ///   - pid: The process ID to debug.
    ///   - commandTimeout: Maximum time to wait for a command response (default 30s).
    ///   - Throws: If LLDB fails to start or attach.
    public init(pid: Int32, commandTimeout: TimeInterval = 30) throws(LLDBError) {
        targetPID = pid
        self.commandTimeout = commandTimeout

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/lldb")
        proc.arguments = ["--no-use-colors"]

        // Use a PTY for stdin+stdout so LLDB emits interactive prompts.
        let (primaryFD, replicaFD) = try openPTY()
        let replicaHandle = FileHandle(fileDescriptor: replicaFD, closeOnDealloc: false)
        proc.standardInput = replicaHandle
        proc.standardOutput = replicaHandle

        let stderrPipe = Pipe()
        proc.standardError = stderrPipe

        process = proc
        // Write to the primary side to send to LLDB's stdin
        stdin = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: false)
        // Read from the primary side to get LLDB's stdout
        stdout = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: false)
        stderr = stderrPipe.fileHandleForReading
        ptyFDs = [primaryFD, replicaFD]

        do {
            try proc.run()
        } catch {
            throw LLDBError.commandFailed("Failed to start LLDB process: \(error)")
        }
    }

    /// Waits for the initial LLDB prompt, then attaches to the target process.
    ///
    /// Must be called exactly once after `init` before sending other commands.
    /// - Returns: The attach command output.
    @discardableResult
    public func attach() async throws(LLDBError) -> String {
        // Wait for initial prompt
        _ = try await readUntilPrompt()
        // Attach to the target process
        let output = try await sendCommand("process attach --pid \(targetPID)")
        // LLDB reports a contended attach as "Process <pid> exited with status = -1 ... tried to
        // attach to process already being debugged", which falsely implies the target died. Surface
        // the real cause instead.
        if Self.outputIndicatesAlreadyDebugged(output) {
            throw LLDBError.commandFailed(
                "Process \(targetPID) is already under another debugger (e.g. Xcode). Detach the other debugger first, then retry. (The target is still running — it did not exit.)",
            )
        }
        return output
    }

    /// Whether LLDB output indicates the target is already attached by another debugger.
    ///
    /// Pure and `static` for unit testing without a live attach.
    static func outputIndicatesAlreadyDebugged(_ output: String) -> Bool {
        output.contains("already being debugged")
    }

    /// Launches a new process under the debugger.
    ///
    /// Must be called exactly once after `init` (instead of `attach` ) before sending other
    /// commands.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the executable to launch.
    ///   - environment: Environment variables to set before launch.
    ///   - arguments: Command-line arguments to pass to the process.
    ///   - stopAtEntry: If true, stops at the entry point before running.
    ///   - Returns: The launch command output.
    @discardableResult
    public func launch(
        executablePath: String,
        environment: [String: String] = [:],
        arguments: [String] = [],
        stopAtEntry: Bool = false,
    ) async throws(LLDBError) -> String {
        // Wait for initial prompt
        _ = try await readUntilPrompt()

        // Set the executable
        let fileOutput = try await sendCommand("file \"\(executablePath)\"")

        // Set environment variables
        for (key, value) in environment {
            _ = try await sendCommand(
                "settings set target.env-vars \(key)=\(value)",
            )
        }

        // Build launch command
        var launchCommand = "process launch"
        if stopAtEntry { launchCommand += " --stop-at-entry" }

        if !arguments.isEmpty {
            let escapedArgs = arguments.map { "\"\($0)\"" }.joined(separator: " ")
            launchCommand += " -- \(escapedArgs)"
        }

        let launchOutput = try await sendCommand(launchCommand)

        // Parse PID from output like "Process 12345 launched"
        if let range = launchOutput.range(
            of: #"Process (\d+) launched"#, options: .regularExpression,
        ) {
            let match = launchOutput[range]
            let digits = match.split(separator: " ")[1]
            if let pid = Int32(digits) { targetPID = pid }
        }

        return fileOutput + "\n" + launchOutput
    }

    /// Drains any pending LLDB output that accumulated asynchronously.
    ///
    /// After `sendCommandNoWait` (used for `continue` ), LLDB may emit output when the process
    /// stops (breakpoint hit, crash, signal). This output sits in the PTY buffer. If not drained,
    /// `readUntilPrompt` would return the stale output instead of the response to the next command.
    ///
    /// Uses `poll()` to check for pending data without blocking, then reads complete
    /// prompt-delimited chunks via `readUntilPrompt()` .
    func drainPendingOutput() async {
        let fd = stdout.fileDescriptor

        for _ in 0..<10 {
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let result = poll(&pollFD, 1, 0)
            guard result > 0, pollFD.revents & Int16(POLLIN) != 0 else { return }

            guard let output = try? await readUntilPrompt() else { return }
            updateProcessState(from: output)
        }
    }

    /// Sends a command to the LLDB process and waits for the response.
    ///
    /// - Parameter command: The LLDB command to execute.
    /// - Returns: The output produced by the command.
    /// - Throws: ``LLDBError/commandFailed(_:)`` on timeout or if the process has exited.
    public func sendCommand(_ command: String) async throws(LLDBError) -> String {
        guard process.isRunning else {
            throw LLDBError.commandFailed("LLDB process is no longer running")
        }
        guard !isPoisoned else {
            throw LLDBError.commandFailed(
                "LLDB session is poisoned by a previous timeout — session will be recreated",
            )
        }

        // Drain any stale output from async events (e.g. breakpoint hit after continue)
        await drainPendingOutput()

        let commandData = Data((command + "\n").utf8)

        do {
            try stdin.write(contentsOf: commandData)
        } catch {
            throw LLDBError.commandFailed("Failed to write to LLDB stdin: \(error)")
        }

        let output = try await readUntilPrompt()

        // Update process state from output
        updateProcessState(from: output)

        return output
    }

    /// Sends a command without waiting for the prompt to return.
    ///
    /// Used for commands like `continue` where LLDB won't show a prompt until the process stops
    /// again. Returns immediately with a confirmation message.
    ///
    /// - Parameter command: The LLDB command to execute.
    /// - Throws: ``LLDBError/commandFailed(_:)`` if the process has exited.
    public func sendCommandNoWait(_ command: String) throws(LLDBError) {
        guard process.isRunning else {
            throw LLDBError.commandFailed("LLDB process is no longer running")
        }
        guard !isPoisoned else {
            throw LLDBError.commandFailed(
                "LLDB session is poisoned by a previous timeout — session will be recreated",
            )
        }

        let commandData = Data((command + "\n").utf8)

        do {
            try stdin.write(contentsOf: commandData)
        } catch {
            throw LLDBError.commandFailed("Failed to write to LLDB stdin: \(error)")
        }
    }

    /// Terminates the LLDB process and closes PTY file descriptors.
    ///
    /// Sends `quit` to LLDB and waits for exit, escalating to SIGTERM then SIGKILL if needed.
    /// Also reaps the `lldb-rpc-server` child: `lldb` spawns it as a child process that does
    /// **not** die when `lldb` is killed (it reparents to launchd and keeps running), so a
    /// cancelled/timed-out/force-killed session would otherwise leak a stale `lldb-rpc-server`
    /// that wedges the next debug launch.
    public func terminate() async {
        let lldbPID = process.processIdentifier
        // Capture child pids now, while lldb is still their parent — once lldb exits they
        // reparent to launchd and can no longer be found via `pgrep -P <lldbPID>`.
        let rpcServerPIDs = lldbPID > 0 ? await Self.childPIDs(ofParent: lldbPID) : []

        if process.isRunning {
            // Try graceful quit first
            let quitData = Data("quit\n".utf8)
            try? stdin.write(contentsOf: quitData)

            let exited = await ProcessResult.waitForProcessExit(pid: lldbPID, timeout: .seconds(2))

            if !exited, process.isRunning {
                process.terminate()  // SIGTERM
                let exitedAfterTerm = await ProcessResult.waitForProcessExit(
                    pid: lldbPID,
                    timeout: .seconds(3),
                )
                if !exitedAfterTerm, process.isRunning { kill(lldbPID, SIGKILL) }
            }
        }

        // Reap any lldb-rpc-server child that outlived lldb. A graceful quit usually takes it
        // down already, in which case `kill(pid, 0)` reports it gone and we skip it.
        for child in rpcServerPIDs where kill(child, 0) == 0 {
            kill(child, SIGKILL)
        }

        for fd in ptyFDs { close(fd) }
    }

    /// Returns the PIDs of the direct child processes of `parent` via `pgrep -P`.
    static func childPIDs(ofParent parent: Int32) async -> [Int32] {
        guard
            let result = try? await ProcessResult.run(
                "/usr/bin/pgrep", arguments: ["-P", "\(parent)"], mergeStderr: false,
            ),
            result.succeeded
        else { return [] }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// Upper bound on output a single command may produce before we treat it as a runaway flood.
    ///
    /// A breakpoint on a high-frequency symbol (e.g. `sqlite3_prepare_v2`, `malloc`,
    /// `objc_msgSend`) — especially with an inferior-function-calling condition — makes LLDB emit
    /// stop/continue chatter faster than it ever returns a clean `(lldb) ` prompt. The reader would
    /// otherwise grow an unbounded string and spin a CPU core, starving the cooperative pool so the
    /// timeout `Task` never even gets scheduled (the >1h13m wedge in dq5-oel). Capping total bytes
    /// lets the read abort in bounded time and memory regardless of scheduler pressure.
    static let maxResponseBytes = 1_000_000

    /// Reads output from LLDB until the `(lldb) ` prompt appears.
    ///
    /// Uses a lock-guarded flag to ensure the continuation is resumed exactly once. On timeout or a
    /// runaway-output flood, marks the session as poisoned so it will be recreated on next use.
    func readUntilPrompt() async throws(LLDBError) -> String {
        let promptMarker = "(lldb) "

        do {
            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<String, any Error>) in
                // One-shot guard ensures the continuation is resumed exactly once.
                let gate = OneShotContinuation(continuation)
                // Shared accumulator so timeout handler can report partial output.
                let partialOutput = Mutex("")
                // Set once the gate has been resolved (by reader, flood guard, or timeout) so the
                // reader thread stops promptly instead of spinning on flooding output forever.
                let finished = Mutex(false)

                let finish: @Sendable (Bool) -> Void = { resumed in
                    if resumed { finished.withLock { $0 = true } }
                }

                // Reader: runs on a GCD thread because FileHandle.availableData blocks.
                DispatchQueue.global().async { [stdout] in
                    var accumulated = ""
                    var buffer = Data()
                    var totalBytes = 0
                    while true {
                        // Bail out the moment another path (timeout) has already resolved the gate,
                        // so a hot breakpoint flooding the PTY can't keep this thread spinning.
                        if finished.withLock({ $0 }) { return }

                        let chunk = stdout.availableData

                        if chunk.isEmpty {
                            // EOF — process exited
                            finish(gate.resume(returning: accumulated))
                            return
                        }
                        totalBytes += chunk.count
                        buffer.append(chunk)

                        if let str = String(data: buffer, encoding: .utf8) {
                            buffer = Data()
                            accumulated += str
                            partialOutput.withLock { $0 = accumulated }

                            if accumulated.hasSuffix(promptMarker) {
                                // Strip the trailing prompt from the output
                                let endIndex = accumulated.index(
                                    accumulated.endIndex, offsetBy: -promptMarker.count,
                                )
                                finish(gate.resume(returning: String(
                                    accumulated[accumulated.startIndex..<endIndex],
                                )))
                                return
                            }
                        }

                        // Flood guard: a bounded amount of output without ever seeing a prompt means
                        // the target is emitting faster than LLDB hands back control.
                        if totalBytes > Self.maxResponseBytes {
                            finish(gate.resume(throwing: LLDBError.commandFailed(
                                "LLDB emitted over \(Self.maxResponseBytes / 1000)KB without returning a prompt — the target is flooding output, typically a breakpoint on a high-frequency symbol (sqlite3_prepare_v2, malloc, objc_msgSend, …) or an inferior-function-calling condition. Aborting to avoid a wedged session; recreate the session and use a narrower breakpoint.",
                            )))
                            return
                        }
                    }
                }

                // Timeout: uses Task.sleep instead of DispatchQueue.asyncAfter.
                let timeout = self.commandTimeout
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    let partial = partialOutput.withLock { $0 }
                    let detail: String
                    if partial.isEmpty {
                        detail = "Timed out waiting for LLDB response (no output received)"
                    } else {
                        let maxChars = 2000
                        let truncated = partial.count > maxChars
                            ? "...\(partial.suffix(maxChars))"
                            : partial
                        detail =
                            "Timed out waiting for LLDB response. Partial output:\n\(truncated)"
                    }
                    let resumed = gate.resume(throwing: LLDBError.commandFailed(detail))
                    finish(resumed)
                    if resumed, let self { await markPoisoned() }
                }
            }
        } catch let error as LLDBError {
            // A flood abort wedges the session just as a timeout does — poison it so the manager
            // recreates a clean LLDB on next use rather than reusing one mid-flood.
            markPoisoned()
            throw error
        } catch {
            markPoisoned()
            throw .commandFailed("\(error)")
        }
    }

    /// Marks this session as poisoned so it will be discarded and recreated.
    private func markPoisoned() { isPoisoned = true }

    /// Parses LLDB output and updates the tracked process state.
    private func updateProcessState(from output: String) {
        if let newState = Self.parseProcessState(from: output) {
            processState = newState
        }
    }

    /// Derives a ``ProcessState`` from LLDB output, or `nil` if the output carries no run/stop
    /// signal (in which case the caller should leave the tracked state unchanged).
    ///
    /// Pure and `static` so the run/stop classification can be unit-tested without a live session.
    static func parseProcessState(from output: String) -> ProcessState? {
        // Process exit always wins — it can co-occur with a stale "stopped" line in the same chunk.
        if output.contains("exited with status") || output.contains("exited with signal") {
            return .stopped(reason: "exited")
        }
        // Look for stop reason patterns in LLDB output
        if let reasonRange = output.range(
            of: #"stop reason = (.+)"#, options: .regularExpression,
        ) {
            let reason = String(output[reasonRange]).replacingOccurrences(
                of: "stop reason = ", with: "",
            )
            return .stopped(reason: reason)
        } else if output.contains("Process"), output.contains("stopped") {
            return .stopped(reason: nil)
        } else if output.contains("Process"), output.contains("resuming") {
            return .running
        }
        return nil
    }

    /// Reconciles the tracked state with reality when the process is believed to be running.
    ///
    /// After `continue` is sent via ``sendCommandNoWait(_:)``, a breakpoint hit (or crash) emits an
    /// async stop notification into the PTY with no command driving it. Until that output is drained,
    /// `processState` stays `.running` even though the target is parked at the breakpoint — the
    /// "is running" desync in 1wa-p8i. This polls the PTY non-blockingly and, if a stop notification
    /// is waiting, reads it and updates the state. Cheap no-op when genuinely running (poll finds no
    /// pending data) or already stopped.
    ///
    /// - Returns: The reconciled process state.
    public func syncedProcessState() async -> ProcessState {
        if case .running = processState {
            await drainPendingOutput()
        }
        return processState
    }

    /// Interrupts a running process and waits for the stop notification.
    ///
    /// `process interrupt` is asynchronous — LLDB may return its prompt before the target actually
    /// stops. This method sends the command, then polls for the async stop notification (up to
    /// `timeout` ) and updates `processState` once the stop is confirmed.
    ///
    /// - Parameter timeout: Maximum time to wait for the stop. Defaults to 5 seconds.
    /// - Returns: The combined output from the interrupt and stop notification.
    public func interruptProcess(
        timeout: Duration = .seconds(5),
    ) async throws(LLDBError) -> String {
        // Send the interrupt command — may return immediately with little output
        let initialOutput = try await sendCommand("process interrupt")

        // If the initial output already contains a stop reason, we're done
        if initialOutput.contains("stop reason") || initialOutput.contains("stopped") {
            processState = .stopped(reason: extractStopReason(from: initialOutput))
            return initialOutput
        }

        // Poll for the async stop notification
        let deadline = ContinuousClock.now + timeout
        let fd = stdout.fileDescriptor

        while ContinuousClock.now < deadline {
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remaining = deadline - .now
            let pollTimeoutMs = max(
                Int32(
                    remaining.components.seconds * 1000 + remaining.components
                        .attoseconds / 1_000_000_000_000_000,
                ),
                0,
            )
            let pollResult = poll(&pollFD, 1, min(pollTimeoutMs, 100))

            if pollResult > 0, pollFD.revents & Int16(POLLIN) != 0 {
                if let stopOutput = try? await readUntilPrompt() {
                    updateProcessState(from: stopOutput)
                    return initialOutput + "\n" + stopOutput
                }
            }
        }

        // Timed out waiting for stop — set stopped anyway since interrupt was sent
        processState = .stopped(reason: "interrupt")
        return initialOutput
    }

    /// Collects asynchronous output (no `(lldb) ` prompt expected) until `marker` has appeared
    /// `count` times or `timeout` elapses.
    ///
    /// Auto-continuing breakpoints (`--auto-continue true`) print their attached commands while the
    /// process keeps running, so no prompt delimits the output. This polls the PTY and accumulates
    /// chunks, stopping once enough markers are seen, the deadline passes, or the same byte cap as
    /// ``readUntilPrompt()`` is hit (so a hot breakpoint can't flood unbounded).
    ///
    /// - Returns: The accumulated output (markers included; the caller strips them).
    func collectUntilMarker(
        _ marker: String,
        count: Int,
        timeout: Duration,
    ) async -> (output: String, hits: Int) {
        let fd = stdout.fileDescriptor
        var accumulated = ""
        var buffer = Data()
        var totalBytes = 0
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&pollFD, 1, 100) > 0, pollFD.revents & Int16(POLLIN) != 0 else { continue }

            let chunk = stdout.availableData
            if chunk.isEmpty { break }  // EOF — process exited
            totalBytes += chunk.count
            buffer.append(chunk)

            if let str = String(data: buffer, encoding: .utf8) {
                buffer = Data()
                accumulated += str
            }

            let hits = accumulated.components(separatedBy: marker).count - 1
            if hits >= count { return (accumulated, hits) }
            if totalBytes > Self.maxResponseBytes { break }
        }

        let hits = accumulated.components(separatedBy: marker).count - 1
        return (accumulated, hits)
    }

    /// Extracts the stop reason string from LLDB output, if present.
    private func extractStopReason(from output: String) -> String? {
        guard let range = output.range(of: #"stop reason = (.+)"#, options: .regularExpression)
        else { return nil }
        return String(output[range]).replacingOccurrences(of: "stop reason = ", with: "")
    }

    /// Checks if the debugged process crashed shortly after a `continue` command.
    ///
    /// After launching and continuing, some processes crash immediately (e.g. dyld symbol
    /// resolution failures, missing frameworks). This method sleeps for `delay` to give the process
    /// time to crash, then uses `poll()` to check if LLDB has emitted any output (crash info +
    /// prompt). If data is available, reads it via `readUntilPrompt()` and returns the crash
    /// output. If no data is pending, the process is running normally and returns `nil` .
    ///
    /// Does **not** poison the session — on timeout the session remains usable.
    ///
    /// - Parameter delay: How long to wait before checking. Defaults to 1.5 seconds.
    /// - Returns: The crash/stop output from LLDB, or `nil` if the process is running.
    /// Patterns that indicate a real crash or abnormal stop in LLDB output.
    private static let crashIndicators: [String] = [
        "stop reason = signal",
        "stop reason = EXC_",
        "EXC_BAD_ACCESS",
        "EXC_BAD_INSTRUCTION",
        "EXC_CRASH",
        "Process ",  // prefix for "Process NNN exited"
    ]

    /// Checks whether LLDB output contains indicators of a real crash or process exit.
    static func outputIndicatesCrash(_ output: String) -> Bool {
        // Check for process exit (e.g. "Process 12345 exited with status = 1")
        if output.contains("exited with status") || output.contains("exited with signal") {
            return true
        }
        // Check for crash-related stop reasons
        for indicator in crashIndicators
        where indicator.starts(with: "stop reason") || indicator.starts(with: "EXC_") {
            if output.contains(indicator) { return true }
        }
        return false
    }

    public func checkForEarlyCrash(
        delay: Duration = .milliseconds(1500),
    ) async -> String? {
        try? await Task.sleep(for: delay)

        // Use poll() to check if LLDB has pending output without blocking. If the process crashed,
        // LLDB will have emitted stop info + a new prompt.
        let fd = stdout.fileDescriptor
        var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollResult = poll(&pollFD, 1, 0)

        guard pollResult > 0, pollFD.revents & Int16(POLLIN) != 0 else { return nil }

        // Data is available — read it and check for actual crash indicators. readUntilPrompt should
        // return quickly since data is already buffered.
        guard let output = try? await readUntilPrompt() else { return nil }
        updateProcessState(from: output)

        // Only report a crash if the output contains semantic crash indicators. Benign output
        // (library loads, startup logs, attach noise) is ignored.
        guard Self.outputIndicatesCrash(output) else { return nil }
        return output
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
    public func createSession(pid: Int32) async throws(LLDBError) -> LLDBSession {
        if let existing = sessions[pid], await existing.isAlive { return existing }

        // Clean up any dead or poisoned session for this PID
        if let old = sessions[pid] { await old.terminate() }
        sessions.removeValue(forKey: pid)

        let session = try LLDBSession(pid: pid)
        try await session.attach()
        sessions[pid] = session
        return session
    }

    /// Creates a new persistent LLDB session that launches a process.
    ///
    /// Unlike `createSession(pid:)` which attaches to an existing process, this launches a new
    /// process under the debugger.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the executable to launch.
    ///   - environment: Environment variables to set before launch.
    ///   - arguments: Command-line arguments to pass to the process.
    ///   - stopAtEntry: If true, stops at the entry point before running.
    ///   - Returns: The LLDB session with the launched process.
    public func createLaunchSession(
        executablePath: String,
        environment: [String: String] = [:],
        arguments: [String] = [],
        stopAtEntry: Bool = false,
        commandTimeout: TimeInterval = 30,
    ) async throws(LLDBError) -> LLDBSession {
        let session = try LLDBSession(pid: 0, commandTimeout: commandTimeout)
        try await session.launch(
            executablePath: executablePath,
            environment: environment,
            arguments: arguments,
            stopAtEntry: stopAtEntry,
        )
        // The long launch window only applies to bringing the process up. Subsequent inspection
        // commands must fail fast instead of hanging for the full launch timeout.
        await session.setCommandTimeout(LLDBSession.interactiveCommandTimeout)
        let pid = await session.targetPID
        if pid > 0 { sessions[pid] = session }
        return session
    }

    /// Creates an LLDB session that launches an app via `/usr/bin/open` and attaches with
    /// `--waitfor` .
    ///
    /// This mimics Xcode's debugger behavior: launch the app through Launch Services (which handles
    /// `@rpath` , sandbox setup, and code signing correctly), then attach LLDB. This avoids the
    /// SIGABRT in dyld that occurs when launching signed/sandboxed macOS apps directly via LLDB's
    /// `process launch` .
    ///
    /// - Parameters:
    ///   - appPath: Path to the .app bundle.
    ///   - executableName: Name of the executable inside the bundle (used for `--waitfor` ).
    ///   - arguments: Command-line arguments to pass to the app via `--args` .
    ///   - environment: Environment variables to set on the launched process.
    ///   - stopAtEntry: If true, leaves the process stopped after attach.
    ///   - Returns: The LLDB session with the attached process.
    public func createOpenAndAttachSession(
        appPath: String,
        executableName: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        stopAtEntry: Bool = false,
    ) async throws(LLDBError) -> LLDBSession {
        // Create a session with a long timeout — waitfor blocks until the process appears
        let session = try LLDBSession(pid: 0, commandTimeout: 120)

        do {
            return try await runOpenAndAttach(
                session: session,
                appPath: appPath,
                executableName: executableName,
                arguments: arguments,
                environment: environment,
                stopAtEntry: stopAtEntry,
            )
        } catch {
            // Any failure before the session is fully established (e.g. a waitfor/attach
            // timeout, or the tool task being cancelled) must reap LLDB and its
            // lldb-rpc-server child — otherwise the next launch attaches against a wedged
            // stale session.
            await session.terminate()
            throw error
        }
    }

    private func runOpenAndAttach(
        session: LLDBSession,
        appPath: String,
        executableName: String,
        arguments: [String],
        environment: [String: String],
        stopAtEntry: Bool,
    ) async throws(LLDBError) -> LLDBSession {
        // Consume the initial LLDB prompt
        _ = try await session.readUntilPrompt()

        // Tell LLDB to wait for a process with this name to appear
        try await session.sendCommandNoWait(
            "process attach --name \"\(executableName)\" --waitfor",
        )

        // Kill any existing instances of the app to avoid attaching to a stale process
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", appPath]
        try? pkill.run()
        pkill.waitUntilExit()

        // Brief sleep so terminated processes fully exit before we launch a new one
        try? await Task.sleep(for: .milliseconds(500))

        // Launch the app via /usr/bin/open (Launch Services handles @rpath, sandbox, etc.)
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        var openArgs = [appPath]
        if !arguments.isEmpty { openArgs += ["--args"] + arguments }
        openProcess.arguments = openArgs

        // Pass user environment variables through the open process
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment { env[key] = value }
            openProcess.environment = env
        }

        do {
            try openProcess.run()
        } catch {
            throw LLDBError.commandFailed("Failed to launch app via /usr/bin/open: \(error)")
        }
        openProcess.waitUntilExit()

        guard openProcess.terminationStatus == 0 else {
            throw LLDBError.commandFailed(
                "Failed to launch app via /usr/bin/open (exit code \(openProcess.terminationStatus))",
            )
        }

        // Wait for LLDB to complete the attach (it blocks until the named process appears)
        let attachOutput = try await session.readUntilPrompt()

        // The 120s window only covers the blocking `--waitfor` attach above. Now that the process
        // is under debugger control, interactive commands (`thread backtrace`, `frame variable`)
        // must fail fast rather than appear to hang for two minutes if a read wedges.
        await session.setCommandTimeout(LLDBSession.interactiveCommandTimeout)

        // Parse PID from attach output like "Process NNN stopped"
        if let range = attachOutput.range(
            of: #"Process (\d+) stopped"#, options: .regularExpression,
        ) {
            let match = attachOutput[range]
            let digits = match.split(separator: " ")[1]
            if let pid = Int32(digits) { await session.setTargetPID(pid) }
        }

        // Process is stopped after attach
        await session.setProcessState(.stopped(reason: nil))

        let pid = await session.targetPID
        if pid > 0 { sessions[pid] = session }

        // If not stopping at entry, continue execution
        if !stopAtEntry {
            try await session.sendCommandNoWait("continue")
            await session.setProcessState(.running)
        }

        return session
    }

    /// Gets an existing session for a PID.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: The session if one exists and is alive (not poisoned), nil otherwise.
    public func getSession(pid: Int32) async -> LLDBSession? {
        guard let session = sessions[pid] else { return nil }
        if await session.isAlive { return session }
        // Clean up dead or poisoned session
        await session.terminate()
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
        if let session = sessions.removeValue(forKey: pid) { await session.terminate() }
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
    public func getAllSessions() -> [String: Int32] { bundleIdToPID }

    /// Gets or creates a session for a PID.
    ///
    /// - Parameter pid: The process ID.
    /// - Returns: An existing or new LLDB session.
    public func getOrCreateSession(pid: Int32) async throws(LLDBError) -> LLDBSession {
        if let session = await getSession(pid: pid) { return session }
        return try await createSession(pid: pid)
    }
}

/// Wrapper for executing LLDB commands.
///
/// `LLDBRunner` provides a Swift interface for invoking the LLDB debugger. It uses persistent LLDB
/// sessions that stay alive across tool calls, so breakpoints persist and repeated attach/detach
/// cycles are avoided.
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

    /// Returns the current process state for a debug session, or `.unknown` if no session exists.
    ///
    /// Reconciles a stale `.running` state against the PTY first (see
    /// ``LLDBSession/syncedProcessState()``) so a process that has hit a breakpoint since the last
    /// `continue` is reported as stopped rather than running.
    public func getProcessState(pid: Int32) async -> ProcessState {
        guard let session = await LLDBSessionManager.shared.getSession(pid: pid) else {
            return .unknown
        }
        return await session.syncedProcessState()
    }

    /// Checks that the process is stopped and throws a descriptive error if not.
    ///
    /// Use this before sending commands that require a stopped process (e.g. `thread backtrace` ,
    /// `frame variable` , `thread step-*` , expression evaluation).
    public func requireStopped(pid: Int32) async throws(LLDBError) {
        let state = await getProcessState(pid: pid)

        if case .running = state {
            throw .commandFailed(
                "Process \(pid) is running. Interrupt it first (debug_lldb_command with 'process interrupt'), then retry.",
            )
        }
    }

    /// Appended to inspection output when the target was running and got auto-interrupted/resumed,
    /// so the caller knows the process was briefly paused (and that any timing-sensitive state may
    /// have advanced).
    static let autoResumeNote =
        "\n\n(Process was running — auto-interrupted to evaluate, then resumed.)"

    /// Runs `body` with the target guaranteed stopped, transparently interrupting a running process
    /// and resuming it afterward.
    ///
    /// Expression evaluation (`po`/`expr`, view-hierarchy dumps) only works on a stopped process; a
    /// running target silently yields empty output or blocks until the command times out. This
    /// interrupts a running process, runs `body` against the stopped state, then continues it again
    /// so the user's app keeps running. If the process is already stopped (e.g. at a breakpoint),
    /// `body` runs against that state and the process is left stopped — interrupting/resuming would
    /// disturb the breakpoint the user is inspecting.
    ///
    /// - Returns: The body result and whether the process was auto-interrupted and resumed.
    public func withProcessStopped<T: Sendable>(
        pid: Int32,
        _ body: (LLDBSession) async throws(LLDBError) -> T,
    ) async throws(LLDBError) -> (result: T, autoResumed: Bool) {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

        var didInterrupt = false
        if case .running = await session.syncedProcessState() {
            _ = try await session.interruptProcess()
            didInterrupt = true
        }

        let result: T
        do {
            result = try await body(session)
        } catch {
            // Resume even on failure so a transient eval error doesn't leave the app frozen.
            if didInterrupt {
                try? await session.sendCommandNoWait("continue")
                await session.setProcessState(.running)
            }
            throw error
        }

        if didInterrupt {
            try await session.sendCommandNoWait("continue")
            await session.setProcessState(.running)
        }
        return (result, didInterrupt)
    }

    /// Checks process state and returns a warning if the process is crashed.
    ///
    /// Expression evaluation often fails on crashed processes because the runtime (ObjC/Swift) may
    /// not be fully loaded. Returns a warning string if crashed, `nil` if the process is in a
    /// usable state.
    public func crashWarning(pid: Int32) async -> String? {
        let state = await getProcessState(pid: pid)

        if state.isCrashed {
            if case let .stopped(reason) = state {
                return
                    "Process \(pid) is stopped due to a crash (\(reason ?? "unknown signal")). Expression evaluation may fail. Use debug_stack or debug_variables to inspect the crash state."
            }
        }
        return nil
    }

    /// Attaches to a process by its process ID.
    ///
    /// Creates a persistent LLDB session that stays alive for subsequent commands.
    ///
    /// - Parameter pid: The process ID to attach to.
    /// - Returns: The result containing the attach output.
    public func attachToPID(_ pid: Int32) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.createSession(pid: pid)
        let statusOutput = try await session.sendCommand("process status")
        return .init(exitCode: 0, stdout: statusOutput, stderr: "")
    }

    /// Launches a process under the debugger.
    ///
    /// Creates a persistent LLDB session that launches the executable and keeps it under debugger
    /// control. The returned PID can be used with all other debug commands.
    ///
    /// - Parameters:
    ///   - executablePath: Path to the executable to launch.
    ///   - environment: Environment variables to set before launch.
    ///   - arguments: Command-line arguments to pass to the process.
    ///   - stopAtEntry: If true, stops at the entry point before running.
    ///   - Returns: The result containing launch output and the PID.
    /// Timeout for launch sessions — loading executables and symbols takes longer than normal
    /// commands.
    private static let launchCommandTimeout: TimeInterval = 120

    public func launchProcess(
        executablePath: String,
        environment: [String: String] = [:],
        arguments: [String] = [],
        stopAtEntry: Bool = false,
    ) async throws(LLDBError) -> (result: LLDBResult, pid: Int32) {
        let session = try await LLDBSessionManager.shared.createLaunchSession(
            executablePath: executablePath,
            environment: environment,
            arguments: arguments,
            stopAtEntry: stopAtEntry,
            commandTimeout: Self.launchCommandTimeout,
        )
        let pid = await session.targetPID
        let statusOutput = try await session.sendCommand("process status")
        return (LLDBResult(exitCode: 0, stdout: statusOutput, stderr: ""), pid)
    }

    /// Launches a macOS app via `/usr/bin/open` and attaches LLDB using `--waitfor` .
    ///
    /// This is the correct way to debug signed/sandboxed macOS apps. Launch Services handles
    /// `@rpath` resolution, sandbox setup, and code signing validation that LLDB's `process launch`
    /// bypasses (causing SIGABRT in dyld).
    ///
    /// - Parameters:
    ///   - appPath: Path to the .app bundle.
    ///   - executableName: Name of the executable (for `--waitfor` attach).
    ///   - arguments: Command-line arguments to pass to the app.
    ///   - environment: Environment variables to set.
    ///   - stopAtEntry: If true, stops at the entry point before running.
    ///   - Returns: The result containing attach output and the PID.
    public func launchViaOpenAndAttach(
        appPath: String,
        executableName: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        stopAtEntry: Bool = false,
    ) async throws(LLDBError) -> (result: LLDBResult, pid: Int32) {
        let session = try await LLDBSessionManager.shared.createOpenAndAttachSession(
            appPath: appPath,
            executableName: executableName,
            arguments: arguments,
            environment: environment,
            stopAtEntry: stopAtEntry,
        )
        let pid = await session.targetPID
        let statusOutput: String

        if stopAtEntry {
            // Process is stopped — get status directly
            statusOutput = try await session.sendCommand("process status")
        } else {
            // Process was continued — check if it crashed immediately
            if let crashOutput = await session.checkForEarlyCrash() {
                // Process stopped shortly after launch — get the backtrace
                let backtrace = await (try? session.sendCommand("thread backtrace")) ?? ""
                statusOutput = "Process crashed immediately after launch\n\n" + crashOutput
                    + (backtrace.isEmpty ? "" : "\n\nBacktrace:\n" + backtrace)
            } else {
                statusOutput = "Process \(pid) launched and running under debugger"
            }
        }
        return (LLDBResult(exitCode: 0, stdout: statusOutput, stderr: ""), pid)
    }

    /// Attaches to a process by name.
    ///
    /// - Parameter processName: The name of the process to attach to.
    /// - Returns: The result containing attach output.
    public func attachToProcess(_ processName: String) async throws(LLDBError) -> LLDBResult {
        // For name-based attach, we need a temporary batch approach since we don't know the PID
        // upfront. Use the old batch method.
        try await runBatch(commands: [
            "process attach --name \"\(processName)\"",
            "process status",
        ])
    }

    /// Detaches from a process and terminates the persistent session.
    ///
    /// - Parameter pid: The process ID to detach from.
    /// - Returns: The result containing the detach output.
    public func detach(pid: Int32) async throws(LLDBError) -> LLDBResult {
        guard let session = await LLDBSessionManager.shared.getSession(pid: pid) else {
            // No existing session — nothing to detach from
            return .init(exitCode: 0, stdout: "No active session for PID \(pid)", stderr: "")
        }

        // `detach` can block when the target is wedged (the read for the prompt never
        // completes and the command times out). Treat that as a partial success: the detach
        // was issued, and `removeSession` → `terminate` tears down LLDB and reaps the
        // lldb-rpc-server regardless, so we never leak a stale session on timeout.
        let output = (try? await session.sendCommand("detach"))
            ?? "detach issued (LLDB did not confirm before timeout — session torn down anyway)"
        await LLDBSessionManager.shared.removeSession(pid: pid)
        return LLDBResult(exitCode: 0, stdout: output, stderr: "")
    }

    /// Sets a breakpoint at a symbol (function name).
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - symbol: The symbol name to break on (e.g., function name).
    ///   - Returns: The result containing breakpoint information.
    public func setBreakpoint(pid: Int32, symbol: String) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let setOutput = try await session.sendCommand("breakpoint set --name \"\(symbol)\"")
        let listOutput = try await session.sendCommand("breakpoint list")
        return .init(
            exitCode: 0,
            stdout: setOutput + "\n" + listOutput,
            stderr: "",
        )
    }

    /// Sets a breakpoint at a specific file and line number.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - file: The source file path.
    ///   - line: The line number in the source file.
    ///   - Returns: The result containing breakpoint information.
    public func setBreakpoint(
        pid: Int32,
        file: String,
        line: Int,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let setOutput = try await session.sendCommand(
            "breakpoint set --file \"\(file)\" --line \(line)",
        )
        let listOutput = try await session.sendCommand("breakpoint list")
        return .init(
            exitCode: 0,
            stdout: setOutput + "\n" + listOutput,
            stderr: "",
        )
    }

    /// Lists all breakpoints in the target process.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing breakpoint information.
    public func listBreakpoints(pid: Int32) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand("breakpoint list")
        return .init(exitCode: 0, stdout: output, stderr: "")
    }

    /// Deletes a breakpoint by its ID.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - breakpointId: The breakpoint ID to delete.
    ///   - Returns: The result containing updated breakpoint list.
    public func deleteBreakpoint(
        pid: Int32,
        breakpointId: Int,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let deleteOutput = try await session.sendCommand("breakpoint delete \(breakpointId)")
        let listOutput = try await session.sendCommand("breakpoint list")
        return .init(
            exitCode: 0,
            stdout: deleteOutput + "\n" + listOutput,
            stderr: "",
        )
    }

    /// Continues execution of a stopped process.
    ///
    /// This sends the `continue` command without waiting for LLDB's prompt, because LLDB won't show
    /// a prompt until the process stops again (e.g., at a breakpoint or signal). Waiting would
    /// cause a timeout and poison the session.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result confirming the process was resumed.
    public func continueExecution(pid: Int32) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        try await session.sendCommandNoWait("continue")
        await session.setProcessState(.running)
        return .init(
            exitCode: 0,
            stdout:
                "Process \(pid) resumed. Use debug_stack or debug_variables when the process stops at a breakpoint.",
            stderr: "",
        )
    }

    /// Gets the current stack trace.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - threadIndex: Optional thread index to get backtrace for (all threads if nil).
    ///   - Returns: The result containing stack trace information.
    public func getStack(
        pid: Int32,
        threadIndex: Int? = nil,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

        if let threadIndex {
            _ = try await session.sendCommand("thread select \(threadIndex)")
            let output = try await session.sendCommand("thread backtrace")
            return LLDBResult(exitCode: 0, stdout: output, stderr: "")
        } else {
            let output = try await session.sendCommand("thread backtrace all")
            return LLDBResult(exitCode: 0, stdout: output, stderr: "")
        }
    }

    /// Gets variables in the current stack frame.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - frameIndex: The stack frame index to inspect (0 is current frame).
    ///   - Returns: The result containing variable information.
    public func getVariables(
        pid: Int32,
        frameIndex: Int = 0,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let selectOutput = try await session.sendCommand("frame select \(frameIndex)")
        let varsOutput = try await session.sendCommand("frame variable")
        return .init(
            exitCode: 0,
            stdout: selectOutput + "\n" + varsOutput,
            stderr: "",
        )
    }

    /// Executes a custom LLDB command.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - command: The LLDB command to execute.
    ///   - Returns: The result containing command output.
    public func executeCommand(pid: Int32, command: String) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        // Route `process interrupt` through the dedicated handler that waits for the async stop
        // notification — plain sendCommand races with it.
        if trimmed == "process interrupt" || trimmed.hasPrefix("process interrupt ") {
            return .init(exitCode: 0, stdout: try await session.interruptProcess(), stderr: "")
        }

        // Expression-evaluation commands block (and eventually time out) against a running target.
        // Auto-interrupt → run → resume so a raw `po`/`expr`/`call` works on a live app the same way
        // debug_evaluate does.
        if Self.isExpressionCommand(trimmed) {
            let (output, autoResumed) = try await withProcessStopped(pid: pid) {
                session throws(LLDBError) in try await session.sendCommand(command)
            }
            return .init(
                exitCode: 0,
                stdout: autoResumed ? output + Self.autoResumeNote : output,
                stderr: "",
            )
        }

        return .init(exitCode: 0, stdout: try await session.sendCommand(command), stderr: "")
    }

    /// Whether an LLDB command evaluates an expression (and therefore needs a stopped process).
    ///
    /// Covers the evaluator aliases (`expr`/`expression`, `po`, `p`/`print`, `call`) by their first
    /// whitespace-delimited token so options like `expr -l objc -O --` still match.
    static func isExpressionCommand(_ trimmed: String) -> Bool {
        let head = trimmed.prefix { !$0.isWhitespace }
        return ["expr", "expression", "po", "p", "print", "call"].contains(String(head))
    }

    /// Evaluates an expression in the debugger context.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - expression: The expression to evaluate.
    ///   - language: Optional language ( `"swift"` or `"objc"` ).
    ///   - objectDescription: Whether to use `po` (default true).
    ///   - thread: Optional thread index to select before evaluating.
    ///   - frame: Optional frame index to select before evaluating.
    ///   - Returns: The result containing expression output.
    public func evaluate(
        pid: Int32,
        expression: String,
        language: String?,
        objectDescription: Bool,
        thread: Int? = nil,
        frame: Int? = nil,
    ) async throws(LLDBError) -> LLDBResult {
        // Expression evaluation requires a stopped process; a running target returns empty output
        // (or blocks until timeout). Transparently interrupt → evaluate → resume so a running app
        // can be inspected without the caller having to manage the stop/continue dance.
        let (output, autoResumed) = try await withProcessStopped(pid: pid) {
            session throws(LLDBError) in
            // Select the requested thread/frame first so `self`/locals resolve against the user's
            // breakpoint frame rather than whatever frame LLDB happened to leave selected (e.g. a
            // run-loop frame parked in mach_msg2_trap). Each is a separate command — LLDB does not
            // split a single line on `;`.
            if let thread { _ = try await session.sendCommand("thread select \(thread)") }
            if let frame { _ = try await session.sendCommand("frame select \(frame)") }

            let command: String

            // Bound the inferior call so a hung evaluation (e.g. an AppKit method touched at an
            // arbitrary interrupt point) returns control to LLDB and fails this single call rather
            // than wedging the read and poisoning the shared session (4ui-lsh).
            if let language {
                command = "expr -l \(language) \(LLDBSession.exprTimeoutOptions) -- \(expression)"
            } else if objectDescription {
                command = "expr -O \(LLDBSession.exprTimeoutOptions) -- \(expression)"
            } else {
                command = "expr \(LLDBSession.exprTimeoutOptions) -- \(expression)"
            }
            return try await session.sendCommand(command)
        }
        return .init(
            exitCode: 0,
            stdout: autoResumed ? output + Self.autoResumeNote : output,
            stderr: "",
        )
    }

    /// Lists threads and optionally selects one.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - selectIndex: Optional thread index to switch to.
    ///   - Returns: The result containing thread information.
    public func listThreads(pid: Int32, selectIndex: Int?) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let listOutput = try await session.sendCommand("thread list")

        if let selectIndex {
            let selectOutput = try await session.sendCommand("thread select \(selectIndex)")
            let infoOutput = try await session.sendCommand("thread info")
            return LLDBResult(
                exitCode: 0,
                stdout: listOutput + "\n" + selectOutput + "\n" + infoOutput,
                stderr: "",
            )
        }
        return .init(exitCode: 0, stdout: listOutput, stderr: "")
    }

    /// Manages watchpoints (add, remove, list).
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - action: The action to perform ( `"add"` , `"remove"` , or `"list"` ).
    ///   - variable: Variable name for add action.
    ///   - address: Memory address for add action (alternative to variable).
    ///   - watchpointId: Watchpoint ID for remove action.
    ///   - condition: Optional condition expression for add action.
    ///   - Returns: The result containing watchpoint information.
    public func manageWatchpoint(
        pid: Int32,
        action: String,
        variable: String?,
        address: String?,
        watchpointId: Int?,
        condition: String?,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

        switch action {
            case "add":
                let setOutput: String

                if let variable {
                    setOutput = try await session.sendCommand("watchpoint set variable \(variable)")
                } else if let address {
                    setOutput =
                        try await session
                        .sendCommand("watchpoint set expression -- \(address)")
                } else {
                    throw LLDBError
                        .commandFailed("Either 'variable' or 'address' is required for add")
                }
                var output = setOutput

                if let condition {
                    // Extract watchpoint ID from output to apply condition
                    let modOutput = try await session.sendCommand(
                        "watchpoint modify -c '\(condition)'",
                    )
                    output += "\n" + modOutput
                }
                let listOutput = try await session.sendCommand("watchpoint list")
                return LLDBResult(exitCode: 0, stdout: output + "\n" + listOutput, stderr: "")

            case "remove":
                guard let watchpointId else {
                    throw LLDBError.commandFailed("watchpoint_id is required for remove")
                }
                let deleteOutput =
                    try await session
                    .sendCommand("watchpoint delete \(watchpointId)")
                let listOutput = try await session.sendCommand("watchpoint list")
                return LLDBResult(
                    exitCode: 0,
                    stdout: deleteOutput + "\n" + listOutput,
                    stderr: "",
                )

            case "list":
                let output = try await session.sendCommand("watchpoint list")
                return LLDBResult(exitCode: 0, stdout: output, stderr: "")

            default: throw LLDBError.commandFailed("Unknown watchpoint action: \(action)")
        }
    }

    /// Steps through code execution.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - mode: Step mode ( `"in"` , `"over"` , `"out"` , or `"instruction"` ).
    ///   - Returns: The result containing the new location after stepping.
    public func step(pid: Int32, mode: String) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let command: String

        switch mode {
            case "in": command = "thread step-in"
            case "over": command = "thread step-over"
            case "out": command = "thread step-out"
            case "instruction": command = "thread step-inst"
            default: throw LLDBError.commandFailed("Unknown step mode: \(mode)")
        }
        let stepOutput = try await session.sendCommand(command)
        let frameOutput = try await session.sendCommand("frame info")
        return .init(
            exitCode: 0,
            stdout: stepOutput + "\n" + frameOutput,
            stderr: "",
        )
    }

    /// Reads memory at an address.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - address: The memory address to read (hex string).
    ///   - count: Number of items to read.
    ///   - format: Output format ( `"hex"` , `"bytes"` , `"ascii"` , or `"instruction"` ).
    ///   - size: Item size in bytes (1, 2, 4, or 8).
    ///   - Returns: The result containing memory contents.
    public func readMemory(
        pid: Int32,
        address: String,
        count: Int,
        format: String,
        size: Int,
    ) async throws(LLDBError) -> LLDBResult {
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
            "memory read --size \(size) --format \(fmt) --count \(count) \(address)",
        )
        return .init(exitCode: 0, stdout: output, stderr: "")
    }

    /// Looks up symbols, addresses, and types.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - address: Address to symbolicate.
    ///   - name: Symbol or function name regex.
    ///   - type: Type name to look up.
    ///   - verbose: Whether to use verbose output.
    ///   - Returns: The result containing symbol information.
    public func symbolLookup(
        pid: Int32,
        address: String?,
        name: String?,
        type: String?,
        verbose: Bool,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        var outputs: [String] = []

        if let address {
            let verboseFlag = verbose ? " -v" : ""
            let output = try await session.sendCommand(
                "image lookup --address \(address)\(verboseFlag)",
            )
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

        return .init(exitCode: 0, stdout: outputs.joined(separator: "\n"), stderr: "")
    }

    /// Dumps the UI view hierarchy.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - platform: `"ios"` or `"macos"` .
    ///   - address: Optional specific view address to inspect.
    ///   - constraints: Whether to show Auto Layout constraints.
    ///   - Returns: The result containing the view hierarchy.
    public func viewHierarchy(
        pid: Int32,
        platform: String,
        address: String?,
        constraints: Bool,
    ) async throws(LLDBError) -> LLDBResult {
        // The recursiveDescription/_subtreeDescription expressions run via the expression evaluator,
        // which only works on a stopped process. A running target yields empty output otherwise, so
        // transparently interrupt → dump → resume.
        let (outputs, autoResumed) = try await withProcessStopped(pid: pid) {
            session throws(LLDBError) -> [String] in
            var outputs: [String] = []

            if let address {
                let output = try await session.sendCommand(
                    LLDBSession.objcExprCommand("[(id)\(address) recursiveDescription]"),
                )
                outputs.append(output)

                if constraints {
                    let hOutput = try await session.sendCommand(
                        LLDBSession.objcExprCommand("[(id)\(address) constraintsAffectingLayoutForAxis:0]"),
                    )
                    let vOutput = try await session.sendCommand(
                        LLDBSession.objcExprCommand("[(id)\(address) constraintsAffectingLayoutForAxis:1]"),
                    )
                    outputs.append("Horizontal constraints:\n" + hOutput)
                    outputs.append("Vertical constraints:\n" + vOutput)
                }
            } else if platform == "macos" {
                // mainWindow is nil for a backgrounded or menu-bar app; fall back to the key window,
                // then the first window, so the dump still resolves a content view.
                let output = try await session.sendCommand(
                    LLDBSession.objcExprCommand(
                        "({ NSApplication *app = (NSApplication *)[NSApplication sharedApplication]; NSWindow *w = [app mainWindow]; if (!w) w = [app keyWindow]; if (!w) w = [[app windows] firstObject]; w ? [[w contentView] _subtreeDescription] : (id)@\"No window found (app has no main, key, or ordered windows).\"; })",
                    ),
                )
                outputs.append(output)
            } else {
                let output = try await session.sendCommand(
                    LLDBSession.objcExprCommand(
                        "[[[UIApplication sharedApplication] keyWindow] recursiveDescription]",
                    ),
                )
                outputs.append(output)
            }
            return outputs
        }

        let joined = outputs.joined(separator: "\n\n")
        return .init(
            exitCode: 0,
            stdout: autoResumed ? joined + Self.autoResumeNote : joined,
            stderr: "",
        )
    }

    /// Toggles colored borders on all views in the key window of a running macOS app.
    ///
    /// Uses a stack-based NSView traversal to set or clear CALayer borders on every subview. The
    /// process must be stopped (at a breakpoint or interrupted) for expression evaluation.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target process.
    ///   - enabled: Whether to enable or disable borders.
    ///   - borderWidth: The border width in points.
    ///   - nsColorSelector: The NSColor selector name (e.g. "redColor").
    ///   - Returns: The result containing the count of affected views.
    public func toggleViewBorders(
        pid: Int32,
        enabled: Bool,
        borderWidth: Double,
        nsColorSelector: String,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

        let expression: String
        expression = enabled
            ? LLDBSession.objcExprCommand("@import AppKit; @import QuartzCore; NSArray *wins = [(NSApplication *)[NSApplication sharedApplication] orderedWindows]; NSMutableArray *stack = [NSMutableArray array]; for (NSWindow *w in wins) { if ([w contentView]) [stack addObject:[w contentView]]; } int nViews = 0; while ([stack count] > 0) { NSView *v = [stack lastObject]; [stack removeLastObject]; [v setWantsLayer:YES]; [[v layer] setBorderWidth:\(borderWidth)]; [[v layer] setBorderColor:[[NSColor \(nsColorSelector)] CGColor]]; [stack addObjectsFromArray:[v subviews]]; nViews++; } [NSString stringWithFormat:@\"Borders enabled on %d views across %lu windows\", nViews, (unsigned long)[wins count]]")
            : LLDBSession.objcExprCommand("@import AppKit; @import QuartzCore; NSArray *wins = [(NSApplication *)[NSApplication sharedApplication] orderedWindows]; NSMutableArray *stack = [NSMutableArray array]; for (NSWindow *w in wins) { if ([w contentView]) [stack addObject:[w contentView]]; } int nViews = 0; while ([stack count] > 0) { NSView *v = [stack lastObject]; [stack removeLastObject]; [[v layer] setBorderWidth:0]; [stack addObjectsFromArray:[v subviews]]; nViews++; } [NSString stringWithFormat:@\"Borders disabled on %d views across %lu windows\", nViews, (unsigned long)[wins count]]")

        let output = try await session.sendCommand(expression)
        return .init(exitCode: 0, stdout: output, stderr: "")
    }

    /// Gets the current process status.
    ///
    /// - Parameter pid: The process ID of the target process.
    /// - Returns: The result containing process state information.
    public func processStatus(pid: Int32) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
        let output = try await session.sendCommand("process status")
        return .init(exitCode: 0, stdout: output, stderr: "")
    }

    /// Marker the auto-continue breakpoint prints after each backtrace so capture knows a hit
    /// completed. Distinctive enough not to collide with normal program output.
    static let captureMarker = "<<<XCMCP_BT_CAPTURED>>>"

    /// Builds the `breakpoint set` command for a non-interactive, auto-continuing backtrace capture.
    ///
    /// The breakpoint prints a bounded `bt`, then a sentinel marker, then auto-continues — so the
    /// stack is captured without a follow-up `debug_stack` call and without leaving the target
    /// stopped. Factored out for testing.
    static func captureBreakpointCommand(
        symbol: String,
        condition: String?,
        frameCount: Int?,
    ) -> String {
        var cmd = "breakpoint set --name \"\(symbol)\""
        if let condition, !condition.isEmpty { cmd += " --condition '\(condition)'" }
        let bt = frameCount.map { "bt \($0)" } ?? "bt"
        // Repeated --command entries run in order on each hit; auto-continue resumes afterward.
        cmd += " --auto-continue true --command \"\(bt)\""
        cmd += " --command \"script print('\(captureMarker)')\""
        return cmd
    }

    /// Sets an auto-continuing breakpoint that captures backtraces, resumes the target, collects up
    /// to `maxHits` stacks, then interrupts and removes the breakpoint.
    ///
    /// This is the safe alternative to hand-rolling a conditional breakpoint on a hot symbol: it is
    /// bounded by `timeout` and the output byte cap, so it can never wedge the session the way the
    /// dq5-oel repro did.
    ///
    /// - Parameters:
    ///   - pid: The process ID of the target.
    ///   - symbol: The function/method name to break on.
    ///   - condition: Optional LLDB condition. Prefer register/memory comparisons over inferior
    ///     function calls (the latter are evaluated on every hit).
    ///   - frameCount: Max frames per backtrace (`nil` for full).
    ///   - maxHits: How many backtraces to collect before stopping.
    ///   - timeoutSeconds: Overall capture budget.
    ///   - Returns: The captured backtrace(s) plus any condition advisories.
    public func captureBacktrace(
        pid: Int32,
        symbol: String,
        condition: String?,
        frameCount: Int?,
        maxHits: Int,
        timeoutSeconds: Double,
    ) async throws(LLDBError) -> LLDBResult {
        let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

        let setCmd = Self.captureBreakpointCommand(
            symbol: symbol, condition: condition, frameCount: frameCount,
        )
        let setOutput = try await session.sendCommand(setCmd)

        // Parse the breakpoint id ("Breakpoint N: ...") so we can remove it afterward.
        let breakpointID: Int? = setOutput.range(
            of: #"Breakpoint (\d+):"#, options: .regularExpression,
        ).flatMap { range in
            Int(setOutput[range].dropFirst("Breakpoint ".count).dropLast())
        }

        // Resume only if currently stopped; if already running the breakpoint will still hit.
        if await session.processState.isStopped {
            try await session.sendCommandNoWait("continue")
            await session.setProcessState(.running)
        }

        let (raw, hits) = await session.collectUntilMarker(
            Self.captureMarker, count: max(maxHits, 1), timeout: .seconds(timeoutSeconds),
        )

        // Leave the target stopped and tidy up the capture breakpoint so it stops firing.
        _ = try? await session.interruptProcess()
        if let breakpointID {
            _ = try? await session.sendCommand("breakpoint delete \(breakpointID)")
        }

        let cleaned = raw.replacingOccurrences(of: Self.captureMarker, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let summary: String
        if hits == 0 {
            summary =
                "No backtrace captured within \(timeoutSeconds)s — the breakpoint on '\(symbol)'\(condition.map { " with condition '\($0)'" } ?? "") was not hit (or its condition never matched). The target was left stopped."
        } else {
            summary = "Captured \(hits) backtrace\(hits == 1 ? "" : "s") at '\(symbol)':"
        }

        return .init(exitCode: 0, stdout: summary + (cleaned.isEmpty ? "" : "\n\n" + cleaned), stderr: "")
    }

    /// Executes LLDB in batch mode with a script (used for cases where persistent sessions aren't
    /// applicable).
    private func runBatch(commands: [String]) async throws(LLDBError) -> LLDBResult {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent(
            "lldb_script_\(UUID().uuidString).lldb",
        )

        do {
            let script = commands.joined(separator: "\n")
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            throw .commandFailed("Failed to write LLDB script: \(error)")
        }
        defer { try? FileManager.default.removeItem(at: scriptPath) }

        do {
            let result = try await ProcessResult.runSubprocess(
                .name("lldb"),
                arguments: ["-s", scriptPath.path, "--batch"],
            )
            return LLDBResult(
                exitCode: result.exitCode,
                stdout: result.stdout,
                stderr: result.stderr,
            )
        } catch {
            throw .commandFailed("\(error)")
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
            case let .commandFailed(message): "LLDB command failed: \(message)"
            case let .attachFailed(message): "Failed to attach to process: \(message)"
            case .noActiveSession: "No active debug session"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case .noActiveSession:
                .invalidParams(errorDescription ?? "No active debug session")
            case .commandFailed, .attachFailed:
                .internalError(errorDescription ?? "Debug operation failed")
        }
    }
}
