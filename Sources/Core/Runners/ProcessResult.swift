import MCP
import Darwin
import System
import Foundation
import Subprocess
import Synchronization
import TobaConcurrency

/// Errors that can occur during process execution.
public enum ProcessError: Error, Sendable, LocalizedError, MCPErrorConvertible {
    /// The process exceeded the allowed time limit.
    case timeout(duration: Duration)

    public var errorDescription: String? {
        switch self {
            case let .timeout(duration): "Process timed out after \(duration)"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case let .timeout(duration): .internalError("Process timed out after \(duration)")
        }
    }
}

/// Unified result of a process execution.
///
/// Contains the exit code and captured output from running any command-line process. Used as the
/// common result type for all runner utilities.
public struct ProcessResult: Sendable {
    /// How the process ended.
    ///
    /// A bare exit code cannot tell a status of 11 from a `SIGSEGV`, because
    /// ``ProcessResult/exitCode`` reports the signal number in the signalled case. Callers that
    /// must name the cause in their output read this instead. (74fa1d59)
    public enum Termination: Sendable, Equatable, CustomStringConvertible {
        /// The process called `exit` with this status.
        case exited(Int32)

        /// This signal killed the process.
        case signaled(Int32)

        /// A short phrase naming the status or the signal, for tool output.
        public var description: String {
            switch self {
                case let .exited(code): "exit status \(code)"
                case let .signaled(signal):
                    if let name = strsignal(signal) {
                        "signal \(signal) (\(String(cString: name)))"
                    } else {
                        "signal \(signal)"
                    }
            }
        }

        /// True when the process ended in a way its own code did not choose.
        ///
        /// A non-zero exit status is a normal way for a test command to report a failure, so only a
        /// signal counts here.
        public var isAbnormal: Bool { if case .signaled = self { true } else { false } }

        /// Converts a Subprocess termination status.
        init(_ status: TerminationStatus) {
            switch status {
                case let .exited(code): self = .exited(code)
                case let .signaled(signal): self = .signaled(signal)
            }
        }
    }

    /// How the process ended.
    public let termination: Termination

    /// Standard output captured from the process.
    public let stdout: String

    /// Standard error captured from the process.
    public let stderr: String

    /// True when
    /// ``runSubprocess(_:arguments:workingDirectory:mergeStderr:outputLimit:errorLimit:environment:timeout:settle:onProgress:)``
    /// killed the process group because the child printed its completion marker and then stopped
    /// exiting.
    ///
    /// The exit code means nothing when this is true, because the kill produced it. The output is
    /// whatever arrived before the kill, so a caller must not report it as a whole run.
    /// (74fa1d59, b5f682b1)
    public let settledAfterCompletion: Bool

    /// The process exit code (0 indicates success).
    ///
    /// Reports the signal number when a signal killed the process. Read ``termination`` to tell the
    /// two apart.
    public var exitCode: Int32 {
        switch termination {
            case let .exited(code): code
            case let .signaled(signal): signal
        }
    }

    /// Creates a new process result.
    ///
    /// - Parameters:
    ///   - exitCode: The process exit code (0 indicates success).
    ///   - stdout: Standard output captured from the process.
    ///   - stderr: Standard error captured from the process.
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.init(termination: .exited(exitCode), stdout: stdout, stderr: stderr)
    }

    /// Creates a new process result from a termination reason.
    ///
    /// - Parameters:
    ///   - termination: How the process ended.
    ///   - stdout: Standard output captured from the process.
    ///   - stderr: Standard error captured from the process.
    ///   - settledAfterCompletion: True when the runner killed the process group after its
    ///     completion marker.
    public init(
        termination: Termination,
        stdout: String,
        stderr: String,
        settledAfterCompletion: Bool = false,
    ) {
        self.termination = termination
        self.stdout = stdout
        self.stderr = stderr
        self.settledAfterCompletion = settledAfterCompletion
    }

    /// Whether the command completed successfully (exit code 0).
    public var succeeded: Bool { termination == .exited(0) }

    /// Combined output from stdout and stderr.
    public var output: String {
        if stderr.isEmpty {
            stdout
        } else if stdout.isEmpty {
            stderr
        } else {
            stdout + "\n" + stderr
        }
    }

    /// The most relevant error output: stderr if available, otherwise stdout.
    public var errorOutput: String { stderr.isEmpty ? stdout : stderr }
}

/// A thread-safe, copyable, `Sendable` one-shot flag.
///
/// Used by ``ProcessResult/raceTimeout(_:run:onTimeout:)`` to record that the wall-clock deadline
/// fired before killing the subprocess group. A reference type (rather than a bare `~Copyable`
/// `Mutex`) so it can be shared across the task group's `sending` `addTask` boundary while still
/// being read from the group body.
private final class TimeoutFlag: Sendable {
    private let raised = Mutex(false)
    func raise() { raised(set: true) }
    var isRaised: Bool { raised.withLock { $0 } }
}

/// Holds the spawned child's pid so a canceller can signal its whole process group.
///
/// A reference type so both the spawn closure and the cancellation handler reach one box. A bare
/// `~Copyable` `Mutex` cannot cross a `sending` boundary, which is why ``TimeoutFlag`` is one too.
private final class ProcessGroupBox: Sendable {
    private let pid = Mutex<pid_t>(0)

    /// The process group leader, or 0 before the spawn records it.
    var leader: pid_t { pid.withLock { $0 } }

    /// Records the process group leader, which is the child itself.
    func set(_ value: pid_t) { pid(set: value) }

    /// Sends `SIGKILL` to every process in the child's group, including its grandchildren.
    func killGroup() {
        let value = pid.withLock { $0 }
        if value > 0 { _ = kill(-value, SIGKILL) }
    }
}

/// The spawn inputs both reader paths of ``ProcessResult/runSubprocess`` share.
private struct SubprocessPlan: Sendable {
    let executable: Subprocess.Executable
    let arguments: Subprocess.Arguments
    let workingDirectory: FilePath?
    let environment: Environment
    let platformOptions: PlatformOptions
    let mergeStderr: Bool
    let outputLimit: Int
    let errorLimit: Int

    /// How many bytes of stderr to keep. A merged stream shares the stdout budget.
    var stderrLimit: Int { mergeStderr ? outputLimit : errorLimit }

    /// Builds the result both reader paths return, applying the merge and the truncation note.
    func assemble(
        termination: ProcessResult.Termination,
        stdout: (String, Bool),
        stderr: (String, Bool),
        settled: Bool,
    ) -> ProcessResult {
        var stdoutText = stdout.0
        let wasTruncated = stdout.1 || (mergeStderr && stderr.1)
        if mergeStderr, !stderr.0.isEmpty { stdoutText += "\n" + stderr.0 }

        if wasTruncated {
            stdoutText = "[output truncated — showing last \(outputLimit / 1_048_576)MB]\n"
                + stdoutText
        }
        return .init(
            termination: termination,
            stdout: stdoutText,
            stderr: mergeStderr ? "" : stderr.0,
            settledAfterCompletion: settled,
        )
    }
}

// MARK: - Completion Settle

/// Bounds the wait for a child that finishes its work but does not exit.
///
/// `swift test` blocks reading the test binary's output pipe. A grandchild that inherited that pipe
/// and outlived the test binary holds the pipe open, so the parent sits idle long after the results
/// are complete and its child is a zombie. The runner cannot repair SwiftPM, so it watches the
/// output for a marker that says the work is done and kills the process group once the output goes
/// quiet. (74fa1d59)
public struct CompletionSettle: Sendable {
    /// Returns true when the collected output shows the child finished its work.
    ///
    /// The runner calls this with a rolling tail of recent output, so a marker split across two
    /// chunks still matches.
    public let isComplete: @Sendable (String) -> Bool

    /// How long to wait for a clean exit after the last output that followed the marker.
    public let grace: Duration

    /// Creates a settle policy.
    ///
    /// - Parameters:
    ///   - grace: How long to wait for a clean exit once the output goes quiet.
    ///   - isComplete: Returns true when a tail of the output shows the work is done.
    public init(grace: Duration = .seconds(15), isComplete: @escaping @Sendable (String) -> Bool) {
        self.grace = grace
        self.isComplete = isComplete
    }
}

/// Tracks whether a child printed its completion marker, when it last wrote output, and how much
/// CPU time its process group has burned.
///
/// A reference type so the output callback and the watchdog task can share it across the task
/// group's `sending` boundary, for the reason ``TimeoutFlag`` is one.
///
/// Internal rather than private so a test can drive the marker and the grace period without a
/// subprocess.
final class SettleMonitor: Sendable {
    /// How much recent output to keep, so a marker split across two chunks still matches.
    static let tailLimit = 4096

    /// How much CPU time the group must burn over one grace period to count as still working.
    ///
    /// A child blocked on a pipe read burns none. A child running tests burns seconds per second,
    /// so the threshold sits far below anything a live run produces. (b5f682b1)
    static let workingCPUTime: Duration = .milliseconds(50)

    private struct State {
        var tail = ""
        var isComplete = false
        var lastActivity = ContinuousClock.now
        var cpuTime: Duration?
        var didSettle = false
        var pollCount = 0
    }

    private let policy: CompletionSettle

    /// Returns the CPU time the child's process group has consumed so far, or `nil` when the group
    /// is gone or unreadable.
    private let cpuTime: @Sendable () -> Duration?

    private let state = Mutex(State())

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - policy: The completion marker and the grace period to apply.
    ///   - cpuTime: Reads the process group's cumulative CPU time. The default reports nothing, so
    ///     the marker and the quiet period decide on their own.
    init(_ policy: CompletionSettle, cpuTime: @escaping @Sendable () -> Duration? = { nil }) {
        self.policy = policy
        self.cpuTime = cpuTime
    }

    /// Records one chunk of child output and re-tests the completion marker.
    func observe(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let tail: String = state.withLock { state in
            state.lastActivity = .now
            guard !state.isComplete else { return "" }
            state.tail += chunk
            if state.tail.count > Self.tailLimit {
                state.tail = String(state.tail.suffix(Self.tailLimit))
            }
            return state.tail
        }
        guard !tail.isEmpty, policy.isComplete(tail) else { return }
        // Read the CPU baseline outside the lock, then store it with the marker. The first quiet
        // check compares against it, so it covers the whole first grace period.
        let baseline = cpuTime()
        state.withLock { state in
            state.isComplete = true
            state.tail = ""
            state.cpuTime = baseline
        }
    }

    /// True when the child printed its marker, wrote nothing for the grace period, and did no work
    /// in that time.
    ///
    /// The quiet period alone is not enough. A test binary writes through a 16 KB stdio buffer, so
    /// a slow suite goes quiet for minutes while it runs. CPU time separates that from a child that
    /// finished and stopped exiting. (b5f682b1)
    ///
    /// Counts the call. A settle that never fires is either a watchdog that never polls or a marker
    /// that never arrives, and ``pollCount`` is what tells the two apart.
    func checkSettled() -> Bool {
        let isQuiet: Bool = state.withLock { state in
            state.pollCount += 1
            return state.isComplete && state.lastActivity.duration(to: .now) >= policy.grace
        }
        guard isQuiet else { return false }

        // A group with no live process cannot produce more output, so nothing is left to wait for.
        guard let current = cpuTime() else { return true }

        return state.withLock { state in
            defer { state.cpuTime = current }
            guard let baseline = state.cpuTime,
                  current - baseline >= Self.workingCPUTime else { return true }
            // The child worked through the quiet period, so treat the work as activity and give it
            // another grace period.
            state.lastActivity = .now
            return false
        }
    }

    /// How many times the watchdog asked whether the child settled.
    var pollCount: Int { state.withLock { $0.pollCount } }

    /// Records that the watchdog killed the process group.
    func markSettled() { state.withLock { $0.didSettle = true } }

    /// True when the watchdog killed the process group.
    var didSettle: Bool { state.withLock { $0.didSettle } }
}

// MARK: - Run

extension ProcessResult {
    /// Runs a command asynchronously and captures its output.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable (e.g. "/usr/bin/open").
    ///   - arguments: Command-line arguments.
    ///   - mergeStderr: When true, stderr is merged into stdout (like `2>&1`). When false, stdout
    ///     and stderr are captured separately.
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
    ///   - outputLimit: Maximum bytes to capture from stdout. Defaults to 2MB.
    ///   - errorLimit: Maximum bytes to capture from stderr. Defaults to 2MB.
    ///   - environment: Environment variables for the subprocess. Defaults to `.inherit`.
    ///   - settle: Optional policy that kills the process group once the child prints a completion
    ///     marker and then goes quiet. Use it for a command that can finish its work and still
    ///     block on an inherited pipe.
    ///   - onProgress: Optional callback invoked with each chunk of stdout/stderr as it arrives
    ///     (decoded as UTF-8). Useful for streaming progress updates back to MCP clients during
    ///     long-running commands.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func runSubprocess(
        _ executable: Subprocess.Executable,
        arguments: Subprocess.Arguments = [],
        workingDirectory: FilePath? = nil,
        mergeStderr: Bool = false,
        outputLimit: Int = 2_097_152,
        errorLimit: Int = 2_097_152,
        environment: Environment = .inherit,
        timeout: Duration? = nil,
        settle: CompletionSettle? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> ProcessResult {
        // Spawn the child in its own process group so we can kill the entire tree on cancellation.
        // Without this, killing the immediate child can leave grandchildren (e.g. SPM build
        // plugins) holding the stdout/stderr pipes open, which blocks output collection forever and
        // makes the MCP server appear hung after an ESC cancel.
        let platformOptions: PlatformOptions = {
            var opts = PlatformOptions()
            opts.processGroupID = 0
            opts.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
            return opts
        }()

        // Tracks the spawned process group leader pid so the cancellation handler can SIGKILL the
        // whole group.
        let pgidBox = ProcessGroupBox()

        // Feeds the settle watchdog every chunk of output before the caller sees it. The watchdog
        // also reads the group's CPU time, so a quiet child that is still working stays alive.
        let monitor = settle.map { policy in
            SettleMonitor(policy) { ProcessGroupActivity.cpuTime(ofGroup: pgidBox.leader) }
        }
        let observer: (@Sendable (String) -> Void)?

        if let monitor {
            observer = { chunk in
                monitor.observe(chunk)
                onProgress?(chunk)
            }
        } else {
            observer = onProgress
        }

        let plan = SubprocessPlan(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            platformOptions: platformOptions,
            mergeStderr: mergeStderr,
            outputLimit: outputLimit,
            errorLimit: errorLimit,
        )
        let run: @Sendable () async throws -> ProcessResult = {
            // A settle policy needs the tail of the output while the child still holds the pipe,
            // and only the pipe reader delivers that. Every other caller keeps the Subprocess
            // sequences, whose page-sized reads cost less per byte. (74fa1d59)
            monitor == nil
                ? try await runReadingSequences(
                    plan, group: pgidBox, monitor: monitor, observer: observer,
                )
                : try await runReadingOwnPipes(
                    plan, group: pgidBox, monitor: monitor, observer: observer,
                )
        }
        let killGroup: @Sendable () -> Void = { pgidBox.killGroup() }
        let guardedRun: @Sendable () async throws -> ProcessResult = {
            guard let monitor else { return try await run() }
            return try await watchForSettle(monitor, run: run, onSettle: killGroup)
        }
        return try await withTaskCancellationHandler {
            try await raceTimeout(timeout, run: guardedRun, onTimeout: killGroup)
        } onCancel: { killGroup() }
    }

    /// Reads the child through Subprocess's own `SubprocessOutputSequence`s.
    ///
    /// Keeps the tail on overflow instead of throwing `SubprocessError.outputLimitExceeded`. Build
    /// errors appear at the end of output, so discarding the head preserves what matters.
    private static func runReadingSequences(
        _ plan: SubprocessPlan,
        group: ProcessGroupBox,
        monitor: SettleMonitor?,
        observer: (@Sendable (String) -> Void)?,
    ) async throws -> ProcessResult {
        let outcome = try await Subprocess.run(
            plan.executable,
            arguments: plan.arguments,
            environment: plan.environment,
            workingDirectory: plan.workingDirectory,
            platformOptions: plan.platformOptions,
            input: .inputWriter,
            output: .sequence,
            error: .sequence,
        ) { execution in
            group.set(execution.processIdentifier.value)
            try await execution.standardInputWriter.finish()
            // Always drain both sequences to prevent the child from blocking on a full pipe buffer.
            async let stdout = collectTail(
                from: execution.standardOutput, limit: plan.outputLimit, onProgress: observer,
            )
            async let stderr = collectTail(
                from: execution.standardError,
                limit: plan.stderrLimit,
                onProgress: observer,
            )
            return try await (stdout, stderr)
        }
        return plan.assemble(
            termination: Termination(outcome.terminationStatus),
            stdout: outcome.closureResult.0,
            stderr: outcome.closureResult.1,
            settled: monitor?.didSettle ?? false,
        )
    }

    /// Reads the child through pipes this runner owns and drains with `read(2)`.
    ///
    /// Subprocess reads with `DispatchIO.read(offset:length:queue:)` and resumes its continuation
    /// only when the requested length arrives or the pipe reaches EOF. The length is one page, so
    /// the trailing partial page of a child's output stays invisible for as long as anything holds
    /// the pipe open. That tail is exactly the summary a ``CompletionSettle`` marker looks for.
    /// `read(2)` returns whatever is available, so the marker arrives while it can still matter.
    /// (74fa1d59)
    private static func runReadingOwnPipes(
        _ plan: SubprocessPlan,
        group: ProcessGroupBox,
        monitor: SettleMonitor?,
        observer: (@Sendable (String) -> Void)?,
    ) async throws -> ProcessResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        let outWrite = outPipe.fileHandleForWriting
        let errWrite = errPipe.fileHandleForWriting
        let outRead = outPipe.fileHandleForReading.fileDescriptor
        let errRead = errPipe.fileHandleForReading.fileDescriptor

        defer {
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }

        let outcome = try await Subprocess.run(
            plan.executable,
            arguments: plan.arguments,
            environment: plan.environment,
            workingDirectory: plan.workingDirectory,
            platformOptions: plan.platformOptions,
            input: .none,
            output: .fileDescriptor(
                FileDescriptor(rawValue: outWrite.fileDescriptor),
                closeAfterSpawningProcess: false,
            ),
            error: .fileDescriptor(
                FileDescriptor(rawValue: errWrite.fileDescriptor),
                closeAfterSpawningProcess: false,
            ),
        ) { execution in
            group.set(execution.processIdentifier.value)
            // Close this side's write ends. The child holds its own duplicates, so a reader sees
            // EOF once every one of those closes and not before.
            try? outWrite.close()
            try? errWrite.close()
            async let stdout = drainToEnd(fd: outRead, limit: plan.outputLimit, onChunk: observer)
            async let stderr = drainToEnd(fd: errRead, limit: plan.stderrLimit, onChunk: observer)
            return await (stdout, stderr)
        }
        return plan.assemble(
            termination: Termination(outcome.terminationStatus),
            stdout: outcome.closureResult.0,
            stderr: outcome.closureResult.1,
            settled: monitor?.didSettle ?? false,
        )
    }

    /// Reads `fd` to EOF on its own thread, keeping the last `limit` bytes.
    ///
    /// Runs off the cooperative pool because `read(2)` blocks. Each call hands `onChunk` whatever
    /// the kernel had, which is what makes a partial line visible before EOF. (74fa1d59)
    ///
    /// - Returns: The collected text and whether the limit discarded any of it.
    private static func drainToEnd(
        fd: Int32,
        limit: Int,
        onChunk: (@Sendable (String) -> Void)?,
    ) async -> (String, Bool) {
        // the detached thread resumes this, and a non-escapable Continuation cannot cross into an
        // escaping closure, so the checked form is the one that fits
        await withCheckedContinuation {  // sm:ignore useContinuationNotChecked
            (continuation: CheckedContinuation<(String, Bool), Never>) in
            Thread.detachNewThread {
                var data = Data()
                var truncated = false
                var buffer = [UInt8](repeating: 0, count: 65_536)

                while true {
                    let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                    // A signal interrupts the read without ending the stream.
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { break }
                    let chunk = Data(buffer[0..<count])
                    data.append(chunk)

                    // Compacting at the cap re-copies the whole retained tail on every later chunk,
                    // which is quadratic in a large log. Letting the buffer reach twice the cap
                    // before trimming makes the copying linear overall. The final trim below brings
                    // it back to the cap.
                    if data.count > limit * 2 {
                        data.removeFirst(data.count - limit)
                        truncated = true
                    }
                    onChunk?(String(decoding: chunk, as: UTF8.self))  // sm:ignore useFailableStringInit
                }
                // The loop trims at twice the cap, so bring the result back to the cap exactly.
                // Output between the cap and twice the cap only loses bytes here, so this is also
                // where truncation gets recorded for that range.
                if data.count > limit {
                    data.removeFirst(data.count - limit)
                    truncated = true
                }
                continuation.resume(
                    returning: (String(decoding: data, as: UTF8.self), truncated),  // sm:ignore useFailableStringInit
                )
            }
        }
    }

    /// How often the settle watchdog re-checks the monitor.
    private static let settlePollInterval: Duration = .milliseconds(500)

    /// Runs `run` with a watchdog that kills the process group once the child settles.
    ///
    /// The kill is what lets the collection tasks finally see EOF on the pipes, so `run` returns
    /// its collected output right after. The result carries a signalled termination, which the
    /// `settledAfterCompletion` flag tells the caller to disregard. (74fa1d59)
    ///
    /// `run` goes in a child task rather than in the group body, and the group waits for its value.
    /// That is the shape ``raceTimeout(_:run:onTimeout:)`` uses. The watchdog yields the sentinel
    /// `nil`, so a non-nil element is always `run`'s result.
    ///
    /// Internal rather than private so a test can drive it with a stand-in `run`.
    static func watchForSettle<T: Sendable>(
        _ monitor: SettleMonitor,
        run: @escaping @Sendable () async throws -> T,
        onSettle: @escaping @Sendable () -> Void,
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask(name: "subprocess-run") { try await run() }
            group.addTask(name: "subprocess-settle") {
                while true {
                    // A cancelled sleep ends the watchdog. It never throws out of the group.
                    do { try await Task.sleep(for: settlePollInterval) } catch { return nil }
                    guard monitor.checkSettled() else { continue }
                    monitor.markSettled()
                    onSettle()
                    return nil
                }
            }
            while let next = try await group.next() {
                guard let value = next else { continue }
                group.cancelAll()
                return value
            }
            // Unreachable while the run task is alive: it is the only task that yields a value.
            throw CancellationError()
        }
    }

    /// Collects output from an async buffer sequence, keeping only the last `limit` bytes when the
    /// total exceeds the limit. Returns the collected string and whether truncation occurred.
    private static func collectTail(
        from sequence: SubprocessOutputSequence,
        limit: Int,
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> (String, Bool) {
        var data = Data()
        var truncated = false

        for try await chunk in sequence {
            let chunkData: Data = chunk.withUnsafeBytes { bytes in Data(bytes) }
            data.append(chunkData)

            // See drainToEnd: trimming at the cap is quadratic, so trim at twice the cap and let
            // the final trim below restore the exact limit.
            if data.count > limit * 2 {
                data.removeFirst(data.count - limit)
                truncated = true
            }
            if let onProgress, !chunkData.isEmpty {
                onProgress(String(decoding: chunkData, as: UTF8.self))  // sm:ignore useFailableStringInit
            }
        }
        // The loop trims at twice the cap, so bring the result back to the cap exactly. Output
        // between the cap and twice the cap only loses bytes here, so this is also where truncation
        // gets recorded for that range.
        if data.count > limit {
            data.removeFirst(data.count - limit)
            truncated = true
        }
        return (String(decoding: data, as: UTF8.self), truncated)  // sm:ignore useFailableStringInit
    }

    /// Races a subprocess closure against an optional timeout.
    ///
    /// When timeout is nil, runs the closure directly. When set, uses a task group to race the
    /// subprocess against a sleep, throwing ``ProcessError/timeout(duration:)`` if the deadline is
    /// exceeded.
    ///
    /// On timeout, `onTimeout` runs *before* the throw propagates so callers can SIGKILL the
    /// subprocess group synchronously. Cancelling the `run` task alone only triggers Subprocess's
    /// SIGTERM teardown of the parent — grandchildren (swift-frontend, SPM plugins) survive, hold
    /// the pipes open, and the run task never returns, so the group teardown that awaits it would
    /// hang. (ycq-rdc)
    ///
    /// The kill, however, is exactly what lets the `run` task finally drain its pipes and return a
    /// (signaled) result — so once the deadline fires, *both* children are eligible to finish and
    /// the throwing task group surfaces whichever posts its completion first. Relying on that
    /// ordering is flaky under parallel CI load (the `run` result occasionally wins, swallowing the
    /// timeout). To make the timeout the deterministic winner, the deadline task records a sticky
    /// flag *before* killing; any subsequent `run` completion is therefore known to be a
    /// kill-induced unblock and is reported as a timeout regardless of scheduler ordering.
    /// (ycq-rdc)
    private static func raceTimeout<T: Sendable>(
        _ timeout: Duration?,
        run: @escaping @Sendable () async throws -> T,
        onTimeout: @escaping @Sendable () -> Void = {},
    ) async throws -> T {
        guard let timeout else { return try await run() }
        // A Sendable reference box: the deadline task and the group body both touch the flag
        // concurrently, and a copyable Sendable class is what lets it cross the addTask `sending`
        // boundary (a bare `~Copyable` Mutex cannot).
        let timedOut = TimeoutFlag()
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask(name: "subprocess-run") { try await run() }
            group.addTask(name: "subprocess-timeout") {
                try await Task.sleep(for: timeout)
                // Mark the breach before the kill: the SIGKILL unblocks `run`, so by the time run
                // can complete this flag is already set. The sentinel `nil` distinguishes the
                // deadline task from a genuine `run` result.
                timedOut.raise()
                onTimeout()
                return nil
            }
            let first = (try await group.next()) ?? nil
            group.cancelAll()
            if timedOut.isRaised { throw ProcessError.timeout(duration: timeout) }
            // The only non-timeout finisher is the `run` task, which yields a non-nil value.
            guard let result = first else { throw ProcessError.timeout(duration: timeout) }
            return result
        }
    }

    /// Runs an `xcrun` subtool (e.g. `simctl`, `devicectl`, `xctrace`) with the given arguments.
    ///
    /// Centralizes the `.name("xcrun")` + `[subtool] + arguments` invocation shared by the
    /// simctl/devicectl/xctrace runners. Callers wrap this in their own typed-throws `catch` to map
    /// the failure onto a tool-specific error.
    ///
    /// - Parameters:
    ///   - subtool: The xcrun subtool name (e.g. "simctl").
    ///   - arguments: Arguments passed after the subtool name.
    /// - Returns: A ``ProcessResult`` with exit code and captured output.
    public static func xcrun(
        _ subtool: String,
        arguments: [String],
    ) async throws -> ProcessResult {
        try await runSubprocess(.name("xcrun"), arguments: Arguments([subtool] + arguments))
    }

    /// Discards the result. Useful for fire-and-forget commands like `kill` or `pkill`.
    @discardableResult
    public func ignore() -> ProcessResult { self }
}

// MARK: - Process Lifecycle

public extension ProcessResult {
    /// Polls `kill -0` to check if a process is still alive, returning true if it exits within
    /// timeout.
    ///
    /// - Parameters:
    ///   - pid: The process ID to monitor.
    ///   - timeout: Maximum time to wait for exit.
    /// - Returns: `true` if the process exited within the timeout, `false` if still alive.
    static func waitForProcessExit(
        pid: Int32,
        timeout: Duration = .seconds(5),
    ) async -> Bool {
        // Fast path: the process is already gone.
        kill(pid, 0) != 0
            ? true
            // the detached thread resumes this, and a non-escapable Continuation cannot cross into
            // an escaping closure, so the checked form is the one that fits
            : await withCheckedContinuation {  // sm:ignore useContinuationNotChecked
                (continuation: CheckedContinuation<Bool, Never>) in
                Thread.detachNewThread {
                    continuation.resume(returning: blockingWaitForProcessExit(
                        pid: pid, timeout: timeout))
                }
            }
    }

    /// Blocks the calling thread until `pid` exits or `timeout` elapses, using a kqueue
    /// `EVFILT_PROC`/`NOTE_EXIT` filter. Returns `true` if the process exited.
    ///
    /// Runs synchronously off the cooperative thread pool so its timing is immune to
    /// cooperative-pool starvation.
    private static func blockingWaitForProcessExit(pid: Int32, timeout: Duration) -> Bool {
        let kq = kqueue()
        if kq < 0 { return kill(pid, 0) != 0 }
        defer { close(kq) }

        var change = kevent(
            ident: UInt(pid),
            filter: Int16(truncatingIfNeeded: EVFILT_PROC),
            flags: UInt16(truncatingIfNeeded: EV_ADD | EV_ONESHOT),
            fflags: UInt32(truncatingIfNeeded: NOTE_EXIT),
            data: 0,
            udata: nil,
        )
        // Registration fails (ESRCH) if the process exited between the fast-path check and here —
        // treat that as an exit.
        if kevent(kq, &change, 1, nil, 0, nil) < 0 { return true }

        let (seconds, attoseconds) = timeout.components
        var deadline = timespec(tv_sec: Int(seconds), tv_nsec: Int(attoseconds / 1_000_000_000))
        var event = kevent()
        let n = kevent(kq, nil, 0, &event, 1, &deadline)
        // n > 0: NOTE_EXIT delivered. n == 0: timed out. n < 0: error — confirm via kill.
        return n > 0 ? true : kill(pid, 0) != 0
    }
}

// MARK: - Simctl Helpers

public extension ProcessResult {
    /// Extracts a PID from simctl launch output (format: "bundle_id: 12345").
    var launchedPID: String? {
        let components = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ": ")
        return components.count >= 2 ? components.last : nil
    }
}

// MARK: - File Utilities

public enum FileUtility {
    /// Reads the last N lines from a file using tail.
    public static func readTailLines(path: String, count: Int = 50) async -> String? {
        guard let result = try? await ProcessResult.run(
            "/usr/bin/tail", arguments: ["-n", "\(count)", path], mergeStderr: false,
        ),
              !result.stdout.isEmpty else { return nil }
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

    /// Opens or creates a file for writing log output and returns a `FileHandle` positioned at the
    /// end.
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
        // The stream outlives the call, so an inherited stdin would let it steal bytes from the MCP
        // transport.
        process.standardInput = FileHandle.nullDevice
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
    /// Waits briefly, then checks if the process has exited. If it exited with an error (e.g.,
    /// invalid predicate syntax), reads the output file for error details and throws.
    ///
    /// - Parameters:
    ///   - pid: The process identifier returned by
    ///     ``launchStreamProcess(executable:arguments:outputFile:)``.
    ///   - outputFile: Path to the log output file (may contain error output from the stream
    ///     process).
    /// - Throws: ``MCPError/internalError(_:)`` if the process exited unexpectedly.
    public static func verifyStreamHealth(
        pid: Int32,
        outputFile: String,
    ) async throws(MCPError) {
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return  // Cancelled — skip health check
        }

        // Check if the process is still running via kill(pid, 0)
        let running = kill(pid, 0) == 0
        guard !running else { return }

        // Process died — read output file for error details
        var detail = "Log stream process (PID \(pid)) exited immediately after launch."
        if let data = FileManager.default.contents(atPath: outputFile),
            let output = String(data: data, encoding: .utf8),
            !output.isEmpty { detail += "\nProcess output:\n\(output.prefix(500))" }
        throw .internalError(detail)
    }

    /// Stops a log capture process by PID or pattern-based kill.
    ///
    /// Sends SIGTERM and waits for the process to exit, escalating to SIGKILL if needed.
    ///
    /// - Parameters:
    ///   - pid: Specific process ID to kill. If nil, uses pkill patterns.
    ///   - pkillPatterns: Patterns to pass to `pkill -f` as fallback.
    public static func stopCapture(pid: Int?, pkillPatterns: [String]) async {
        if let pid {
            _ = try? await ProcessResult.run("/bin/kill", arguments: ["\(pid)"])
            let exited = await ProcessResult.waitForProcessExit(pid: Int32(pid))
            if !exited {
                _ = try? await ProcessResult.run("/bin/kill", arguments: ["-9", "\(pid)"])
            }
        } else {
            for pattern in pkillPatterns {
                _ = try? await ProcessResult.run("/usr/bin/pkill", arguments: ["-f", pattern])
            }
            // Brief delay to allow signal delivery for pattern-based kills
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

// MARK: - Process Waiting

public extension Process {
    /// Waits for the process to exit, leaving the cooperative pool free
    ///
    /// `waitUntilExit()` parks a Swift concurrency worker thread for as long as the child runs,
    /// which is unbounded for a recording. This suspends instead.
    ///
    /// The `isRunning` re-check after installing the handler closes a race. A child that exits
    /// before the handler is attached never fires it, and a caller that only waits on the handler
    /// hangs for the whole request.
    func waitForExit() async {
        let resumed = Mutex(false)
        // the termination handler escapes, and a non-escapable Continuation cannot, so the checked
        // form is the one that fits
        await withCheckedContinuation {  // sm:ignore useContinuationNotChecked
            (continuation: CheckedContinuation<Void, Never>) in
            let resumeOnce: @Sendable () -> Void = {
                let isFirst = resumed.withLock { done in
                    if done { return false }
                    done = true
                    return true
                }
                if isFirst { continuation.resume() }
            }
            terminationHandler = { _ in resumeOnce() }
            if !isRunning { resumeOnce() }
        }
    }
}

// MARK: - Process Factory

public extension Process {
    /// Creates (but does not start) an `xcrun` subtool process with its stdio on the null device.
    ///
    /// Used for long-running recordings (`xctrace record`, `simctl io recordVideo`) where the
    /// caller owns the process lifecycle and stops it with SIGINT.
    ///
    /// The null device answers two problems that an inherited or unread descriptor creates. A
    /// recording that inherits the caller's stdout keeps that pipe open for as long as it runs, so
    /// a parent that exits first leaves a reader blocked on a pipe with a live writer. A recording
    /// that writes to a pipe nobody drains blocks once the 64 KB buffer fills. No caller reads
    /// either stream, so discarding both is the correct wiring.
    ///
    /// - Parameters:
    ///   - subtool: The xcrun subtool name (e.g. "xctrace").
    ///   - arguments: Arguments passed after the subtool name.
    /// - Returns: An unstarted `Process`; call `run()` to launch it.
    static func xcrun(_ subtool: String, arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [subtool] + arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
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
