import Foundation
import MCP
import Synchronization

/// Opens a pseudo-TTY pair and returns (primary, replica) file descriptors.
///
/// LLDB suppresses the interactive `(lldb) ` prompt when stdin is a pipe.
/// Using a PTY makes LLDB believe it's connected to a terminal, so it emits
/// prompts that `readUntilPrompt()` can detect.
private func openPTY() throws -> (primary: Int32, replica: Int32) {
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

  // Disable echo and canonical mode on the replica so we don't get
  // our own commands echoed back through the PTY driver.
  var attrs = termios()
  tcgetattr(replica, &attrs)
  attrs.c_lflag &= ~UInt(ECHO | ICANON)
  tcsetattr(replica, TCSANOW, &attrs)

  return (primary, replica)
}

/// A persistent LLDB process that stays alive across tool calls.
///
/// Instead of spawning a new `lldb --batch` process for each command,
/// `LLDBSession` keeps a single LLDB process running and sends commands
/// via stdin, reading responses until the `(lldb) ` prompt reappears.
///
/// Uses a pseudo-TTY so LLDB emits interactive prompts.
public actor LLDBSession {
  private let process: Process
  private let stdin: FileHandle
  private let stdout: FileHandle
  private let stderr: FileHandle
  private let commandTimeout: TimeInterval
  /// File descriptors to close when the session is terminated.
  private let ptyFDs: [Int32]

  /// The PID of the process being debugged.
  public private(set) var targetPID: Int32

  /// Whether the session has been poisoned by a timeout and should be recreated.
  public private(set) var isPoisoned: Bool = false

  /// Whether the LLDB process is still running and the session is usable.
  public var isAlive: Bool {
    process.isRunning && !isPoisoned
  }

  /// Updates the target PID (e.g. after a `--waitfor` attach resolves).
  public func setTargetPID(_ pid: Int32) {
    targetPID = pid
  }

  /// Creates a new persistent LLDB session attached to a process.
  ///
  /// Uses a pseudo-TTY for stdin/stdout so LLDB emits interactive prompts.
  ///
  /// - Parameters:
  ///   - pid: The process ID to debug.
  ///   - commandTimeout: Maximum time to wait for a command response (default 30s).
  /// - Throws: If LLDB fails to start or attach.
  public init(pid: Int32, commandTimeout: TimeInterval = 30) throws {
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

  /// Launches a new process under the debugger.
  ///
  /// Must be called exactly once after `init` (instead of `attach`) before sending other commands.
  ///
  /// - Parameters:
  ///   - executablePath: Path to the executable to launch.
  ///   - environment: Environment variables to set before launch.
  ///   - arguments: Command-line arguments to pass to the process.
  ///   - stopAtEntry: If true, stops at the entry point before running.
  /// - Returns: The launch command output.
  @discardableResult
  public func launch(
    executablePath: String,
    environment: [String: String] = [:],
    arguments: [String] = [],
    stopAtEntry: Bool = false,
  ) async throws -> String {
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
    if stopAtEntry {
      launchCommand += " --stop-at-entry"
    }
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
      if let pid = Int32(digits) {
        targetPID = pid
      }
    }

    return fileOutput + "\n" + launchOutput
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
    guard !isPoisoned else {
      throw LLDBError.commandFailed(
        "LLDB session is poisoned by a previous timeout — session will be recreated",
      )
    }

    let commandData = Data((command + "\n").utf8)
    try stdin.write(contentsOf: commandData)

    return try await readUntilPrompt()
  }

  /// Sends a command without waiting for the prompt to return.
  ///
  /// Used for commands like `continue` where LLDB won't show a prompt
  /// until the process stops again. Returns immediately with a confirmation message.
  ///
  /// - Parameter command: The LLDB command to execute.
  /// - Throws: ``LLDBError/commandFailed(_:)`` if the process has exited.
  public func sendCommandNoWait(_ command: String) throws {
    guard process.isRunning else {
      throw LLDBError.commandFailed("LLDB process is no longer running")
    }
    guard !isPoisoned else {
      throw LLDBError.commandFailed(
        "LLDB session is poisoned by a previous timeout — session will be recreated",
      )
    }

    let commandData = Data((command + "\n").utf8)
    try stdin.write(contentsOf: commandData)
  }

  /// Terminates the LLDB process and closes PTY file descriptors.
  public func terminate() {
    if process.isRunning {
      // Try graceful quit first
      let quitData = Data("quit\n".utf8)
      try? stdin.write(contentsOf: quitData)

      // Give it a moment, then force kill
      let fds = ptyFDs
      let proc = process
      Task {
        try? await Task.sleep(for: .seconds(1))
        if proc.isRunning {
          proc.terminate()
        }
        for fd in fds {
          close(fd)
        }
      }
    } else {
      for fd in ptyFDs {
        close(fd)
      }
    }
  }

  /// Reads output from LLDB until the `(lldb) ` prompt appears.
  ///
  /// Uses a lock-guarded flag to ensure the continuation is resumed exactly once.
  /// On timeout, marks the session as poisoned so it will be recreated on next use.
  func readUntilPrompt() async throws -> String {
    let promptMarker = "(lldb) "

    return try await withCheckedThrowingContinuation { continuation in
      // Guard to ensure the continuation is resumed exactly once.
      let resumed = Mutex(false)
      // Shared accumulator so timeout handler can report partial output.
      let partialOutput = Mutex("")

      let workItem = DispatchWorkItem { [stdout] in
        var accumulated = ""
        var buffer = Data()
        while true {
          let chunk = stdout.availableData
          if chunk.isEmpty {
            // EOF — process exited
            let didResume = resumed.withLock { alreadyResumed -> Bool in
              if alreadyResumed { return false }
              alreadyResumed = true
              return true
            }
            if didResume {
              continuation.resume(returning: accumulated)
            }
            return
          }
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
              let result = String(accumulated[accumulated.startIndex..<endIndex])
              let didResume = resumed.withLock { alreadyResumed -> Bool in
                if alreadyResumed { return false }
                alreadyResumed = true
                return true
              }
              if didResume {
                continuation.resume(returning: result)
              }
              return
            }
          }
        }
      }

      // Timeout handling — marks session as poisoned and resumes with error.
      let timeoutItem = DispatchWorkItem { [weak self] in
        let didResume = resumed.withLock { alreadyResumed -> Bool in
          if alreadyResumed { return false }
          alreadyResumed = true
          return true
        }
        if didResume {
          // Mark session as poisoned. The reader thread may still be alive
          // consuming stdout, but we won't reuse this session.
          if let self {
            Task { await self.markPoisoned() }
          }
          let partial = partialOutput.withLock { $0 }
          let detail: String
          if partial.isEmpty {
            detail =
              "Timed out waiting for LLDB response (no output received)"
          } else {
            // Include last portion of output for diagnostics
            let maxChars = 2000
            let truncated =
              partial.count > maxChars
              ? "...\(partial.suffix(maxChars))" : partial
            detail =
              "Timed out waiting for LLDB response. Partial output:\n\(truncated)"
          }
          continuation.resume(
            throwing: LLDBError.commandFailed(detail),
          )
        }
      }

      DispatchQueue.global().async(execute: workItem)
      DispatchQueue.global().asyncAfter(
        deadline: .now() + self.commandTimeout, execute: timeoutItem,
      )

      // Cancel timeout if work completes first
      workItem.notify(queue: .global()) {
        timeoutItem.cancel()
      }
    }
  }

  /// Marks this session as poisoned so it will be discarded and recreated.
  private func markPoisoned() {
    isPoisoned = true
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

    // Clean up any dead or poisoned session for this PID
    if let old = sessions[pid] {
      await old.terminate()
    }
    sessions.removeValue(forKey: pid)

    let session = try LLDBSession(pid: pid)
    try await session.attach()
    sessions[pid] = session
    return session
  }

  /// Creates a new persistent LLDB session that launches a process.
  ///
  /// Unlike `createSession(pid:)` which attaches to an existing process,
  /// this launches a new process under the debugger.
  ///
  /// - Parameters:
  ///   - executablePath: Path to the executable to launch.
  ///   - environment: Environment variables to set before launch.
  ///   - arguments: Command-line arguments to pass to the process.
  ///   - stopAtEntry: If true, stops at the entry point before running.
  /// - Returns: The LLDB session with the launched process.
  public func createLaunchSession(
    executablePath: String,
    environment: [String: String] = [:],
    arguments: [String] = [],
    stopAtEntry: Bool = false,
    commandTimeout: TimeInterval = 30,
  ) async throws -> LLDBSession {
    let session = try LLDBSession(pid: 0, commandTimeout: commandTimeout)
    try await session.launch(
      executablePath: executablePath,
      environment: environment,
      arguments: arguments,
      stopAtEntry: stopAtEntry,
    )
    let pid = await session.targetPID
    if pid > 0 {
      sessions[pid] = session
    }
    return session
  }

  /// Creates an LLDB session that launches an app via `/usr/bin/open` and attaches with `--waitfor`.
  ///
  /// This mimics Xcode's debugger behavior: launch the app through Launch Services
  /// (which handles `@rpath`, sandbox setup, and code signing correctly), then attach LLDB.
  /// This avoids the SIGABRT in dyld that occurs when launching signed/sandboxed macOS apps
  /// directly via LLDB's `process launch`.
  ///
  /// - Parameters:
  ///   - appPath: Path to the .app bundle.
  ///   - executableName: Name of the executable inside the bundle (used for `--waitfor`).
  ///   - arguments: Command-line arguments to pass to the app via `--args`.
  ///   - environment: Environment variables to set on the launched process.
  ///   - stopAtEntry: If true, leaves the process stopped after attach.
  /// - Returns: The LLDB session with the attached process.
  public func createOpenAndAttachSession(
    appPath: String,
    executableName: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    stopAtEntry: Bool = false,
  ) async throws -> LLDBSession {
    // Create a session with a long timeout — waitfor blocks until the process appears
    let session = try LLDBSession(pid: 0, commandTimeout: 120)

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
    try await Task.sleep(for: .milliseconds(500))

    // Launch the app via /usr/bin/open (Launch Services handles @rpath, sandbox, etc.)
    let openProcess = Process()
    openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    var openArgs = [appPath]
    if !arguments.isEmpty {
      openArgs += ["--args"] + arguments
    }
    openProcess.arguments = openArgs

    // Pass user environment variables through the open process
    if !environment.isEmpty {
      var env = ProcessInfo.processInfo.environment
      for (key, value) in environment {
        env[key] = value
      }
      openProcess.environment = env
    }

    try openProcess.run()
    openProcess.waitUntilExit()

    guard openProcess.terminationStatus == 0 else {
      await session.terminate()
      throw LLDBError.commandFailed(
        "Failed to launch app via /usr/bin/open (exit code \(openProcess.terminationStatus))",
      )
    }

    // Wait for LLDB to complete the attach (it blocks until the named process appears)
    let attachOutput = try await session.readUntilPrompt()

    // Parse PID from attach output like "Process NNN stopped"
    if let range = attachOutput.range(
      of: #"Process (\d+) stopped"#, options: .regularExpression,
    ) {
      let match = attachOutput[range]
      let digits = match.split(separator: " ")[1]
      if let pid = Int32(digits) {
        await session.setTargetPID(pid)
      }
    }

    let pid = await session.targetPID
    if pid > 0 {
      sessions[pid] = session
    }

    // If not stopping at entry, continue execution
    if !stopAtEntry {
      try await session.sendCommandNoWait("continue")
    }

    return session
  }

  /// Gets an existing session for a PID.
  ///
  /// - Parameter pid: The process ID.
  /// - Returns: The session if one exists and is alive (not poisoned), nil otherwise.
  public func getSession(pid: Int32) async -> LLDBSession? {
    guard let session = sessions[pid] else { return nil }
    if await session.isAlive {
      return session
    }
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

  /// Launches a process under the debugger.
  ///
  /// Creates a persistent LLDB session that launches the executable and keeps it
  /// under debugger control. The returned PID can be used with all other debug commands.
  ///
  /// - Parameters:
  ///   - executablePath: Path to the executable to launch.
  ///   - environment: Environment variables to set before launch.
  ///   - arguments: Command-line arguments to pass to the process.
  ///   - stopAtEntry: If true, stops at the entry point before running.
  /// - Returns: The result containing launch output and the PID.
  /// Timeout for launch sessions — loading executables and symbols takes longer than normal commands.
  private static let launchCommandTimeout: TimeInterval = 120

  public func launchProcess(
    executablePath: String,
    environment: [String: String] = [:],
    arguments: [String] = [],
    stopAtEntry: Bool = false,
  ) async throws -> (result: LLDBResult, pid: Int32) {
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

  /// Launches a macOS app via `/usr/bin/open` and attaches LLDB using `--waitfor`.
  ///
  /// This is the correct way to debug signed/sandboxed macOS apps. Launch Services
  /// handles `@rpath` resolution, sandbox setup, and code signing validation that
  /// LLDB's `process launch` bypasses (causing SIGABRT in dyld).
  ///
  /// - Parameters:
  ///   - appPath: Path to the .app bundle.
  ///   - executableName: Name of the executable (for `--waitfor` attach).
  ///   - arguments: Command-line arguments to pass to the app.
  ///   - environment: Environment variables to set.
  ///   - stopAtEntry: If true, stops at the entry point before running.
  /// - Returns: The result containing attach output and the PID.
  public func launchViaOpenAndAttach(
    appPath: String,
    executableName: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    stopAtEntry: Bool = false,
  ) async throws -> (result: LLDBResult, pid: Int32) {
    let session = try await LLDBSessionManager.shared.createOpenAndAttachSession(
      appPath: appPath,
      executableName: executableName,
      arguments: arguments,
      environment: environment,
      stopAtEntry: stopAtEntry,
    )
    let pid = await session.targetPID
    // Get status — if process is running (not stopped), this will time out,
    // so only check status when stopped at entry
    let statusOutput: String
    if stopAtEntry {
      statusOutput = try await session.sendCommand("process status")
    } else {
      statusOutput = "Process \(pid) launched and running under debugger"
    }
    return (LLDBResult(exitCode: 0, stdout: statusOutput, stderr: ""), pid)
  }

  /// Attaches to a process by name.
  ///
  /// - Parameter processName: The name of the process to attach to.
  /// - Returns: The result containing attach output.
  public func attachToProcess(_ processName: String) async throws -> LLDBResult {
    // For name-based attach, we need a temporary batch approach since
    // we don't know the PID upfront. Use the old batch method.
    try await runBatch(commands: [
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
      stderr: "",
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
      "breakpoint set --file \"\(file)\" --line \(line)",
    )
    let listOutput = try await session.sendCommand("breakpoint list")
    return LLDBResult(
      exitCode: 0,
      stdout: setOutput + "\n" + listOutput,
      stderr: "",
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
      stderr: "",
    )
  }

  /// Continues execution of a stopped process.
  ///
  /// This sends the `continue` command without waiting for LLDB's prompt,
  /// because LLDB won't show a prompt until the process stops again (e.g.,
  /// at a breakpoint or signal). Waiting would cause a timeout and poison
  /// the session.
  ///
  /// - Parameter pid: The process ID of the target process.
  /// - Returns: The result confirming the process was resumed.
  public func continueExecution(pid: Int32) async throws -> LLDBResult {
    let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
    try await session.sendCommandNoWait("continue")
    return LLDBResult(
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
      stderr: "",
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
    objectDescription: Bool,
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
        stderr: "",
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
    condition: String?,
  ) async throws -> LLDBResult {
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
        throw
          LLDBError
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
      stderr: "",
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
    size: Int,
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
      "memory read --size \(size) --format \(fmt) --count \(count) \(address)",
    )
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
    verbose: Bool,
  ) async throws -> LLDBResult {
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
    constraints: Bool,
  ) async throws -> LLDBResult {
    let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)
    var outputs: [String] = []

    if let address {
      let output = try await session.sendCommand(
        "expr -l objc -O -- [(id)\(address) recursiveDescription]",
      )
      outputs.append(output)
      if constraints {
        let hOutput = try await session.sendCommand(
          "expr -l objc -O -- [(id)\(address) constraintsAffectingLayoutForAxis:0]",
        )
        let vOutput = try await session.sendCommand(
          "expr -l objc -O -- [(id)\(address) constraintsAffectingLayoutForAxis:1]",
        )
        outputs.append("Horizontal constraints:\n" + hOutput)
        outputs.append("Vertical constraints:\n" + vOutput)
      }
    } else if platform == "macos" {
      let output = try await session.sendCommand(
        "expr -l objc -O -- [[[NSApplication sharedApplication] mainWindow] contentView]._subtreeDescription",
      )
      outputs.append(output)
    } else {
      let output = try await session.sendCommand(
        "expr -l objc -O -- [[[UIApplication sharedApplication] keyWindow] recursiveDescription]",
      )
      outputs.append(output)
    }

    return LLDBResult(exitCode: 0, stdout: outputs.joined(separator: "\n\n"), stderr: "")
  }

  /// Toggles colored borders on all views in the key window of a running macOS app.
  ///
  /// Uses a stack-based NSView traversal to set or clear CALayer borders on every subview.
  /// The process must be stopped (at a breakpoint or interrupted) for expression evaluation.
  ///
  /// - Parameters:
  ///   - pid: The process ID of the target process.
  ///   - enabled: Whether to enable or disable borders.
  ///   - borderWidth: The border width in points.
  ///   - nsColorSelector: The NSColor selector name (e.g. "redColor").
  /// - Returns: The result containing the count of affected views.
  public func toggleViewBorders(
    pid: Int32,
    enabled: Bool,
    borderWidth: Double,
    nsColorSelector: String,
  ) async throws -> LLDBResult {
    let session = try await LLDBSessionManager.shared.getOrCreateSession(pid: pid)

    let expression: String
    if enabled {
      expression =
        "expr -l objc -O -- @import AppKit; @import QuartzCore; NSArray *wins = [(NSApplication *)[NSApplication sharedApplication] orderedWindows]; NSMutableArray *stack = [NSMutableArray array]; for (NSWindow *w in wins) { if ([w contentView]) [stack addObject:[w contentView]]; } int nViews = 0; while ([stack count] > 0) { NSView *v = [stack lastObject]; [stack removeLastObject]; [v setWantsLayer:YES]; [[v layer] setBorderWidth:\(borderWidth)]; [[v layer] setBorderColor:[[NSColor \(nsColorSelector)] CGColor]]; [stack addObjectsFromArray:[v subviews]]; nViews++; } [NSString stringWithFormat:@\"Borders enabled on %d views across %lu windows\", nViews, (unsigned long)[wins count]]"
    } else {
      expression =
        "expr -l objc -O -- @import AppKit; @import QuartzCore; NSArray *wins = [(NSApplication *)[NSApplication sharedApplication] orderedWindows]; NSMutableArray *stack = [NSMutableArray array]; for (NSWindow *w in wins) { if ([w contentView]) [stack addObject:[w contentView]]; } int nViews = 0; while ([stack count] > 0) { NSView *v = [stack lastObject]; [stack removeLastObject]; [[v layer] setBorderWidth:0]; [stack addObjectsFromArray:[v subviews]]; nViews++; } [NSString stringWithFormat:@\"Borders disabled on %d views across %lu windows\", nViews, (unsigned long)[wins count]]"
    }

    let output = try await session.sendCommand(expression)
    return LLDBResult(exitCode: 0, stdout: output, stderr: "")
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
        "lldb_script_\(UUID().uuidString).lldb",
      )

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
          stderr: stderr,
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
