import MCP
import XCMCPCore
import Foundation

public struct StopMacAppTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_mac_app",
            description:
            "Stop (terminate) a running macOS app by its bundle identifier, app name, or process ID.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to stop (e.g., 'com.example.MyApp').",
                        ),
                    ]),
                    "app_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the app to stop (e.g., 'MyApp'). Alternative to bundle_id.",
                        ),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to stop. Useful when the PID is already known from build_debug_macos.",
                        ),
                    ]),
                    "force": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, forcefully terminates the app (SIGKILL). Defaults to false (SIGTERM).",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Validate identifiers at the execution boundary — reject empty/whitespace names before
        // they reach any process-selection command, even if a caller bypasses the tool schema.
        let bundleId = try Self.normalizedIdentifier(arguments.getString("bundle_id"))
        let appName = try Self.normalizedIdentifier(arguments.getString("app_name"))
        let pid = try Self.validatedTargetPID(arguments.getInt("pid"))

        if bundleId == nil, appName == nil, pid == nil {
            throw MCPError.invalidParams(
                "At least one of bundle_id, app_name, or pid is required.",
            )
        }

        let force = arguments.getBool("force")
        let identifier = bundleId ?? appName ?? pid.map { "PID \($0)" } ?? "unknown"

        do {
            // Resolve to a concrete set of PIDs using exact matching (NSRunningApplication /
            // NSWorkspace / LLDB session). Never fall back to `pkill -f`, which matches the full
            // command line as a regex and can terminate unrelated processes.
            let pids: [Int32]
            if let pid {
                pids = [pid]
            } else {
                pids = await resolvePIDs(bundleId: bundleId, appName: appName)
            }

            if pids.isEmpty {
                return Self.notRunning(identifier)
            }

            if force {
                return try await forceKill(pids: pids, identifier: identifier)
            }

            // For GUI apps addressed by bundle id / name, prefer a polite quit (preserves unsaved
            // state) before escalating to signals. A bare PID has no app to "quit", so signal it.
            if bundleId != nil || appName != nil {
                return try await gracefulQuit(
                    bundleId: bundleId, appName: appName, pids: pids, identifier: identifier,
                )
            }
            return try await gracefulKillByPID(pid: pids[0], identifier: identifier)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Trims an optional identifier, rejecting present-but-empty values.
    ///
    /// An empty pattern is the most dangerous input: `pkill -f ""` (or an empty `killall` name)
    /// matches every process. Returns `nil` when the key was absent, the trimmed value when present.
    static func normalizedIdentifier(_ raw: String?) throws(MCPError) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw .invalidParams("bundle_id and app_name must not be empty or whitespace.")
        }
        return trimmed
    }

    /// Validates an optional target PID, rejecting values that would broadcast a signal.
    ///
    /// `kill(2)` treats PID `0` as "every process in the caller's group", negative PIDs as a target
    /// process group, and PID `1` as `launchd`. None of those are legitimate app targets, so we
    /// reject anything ≤ 1 (and out-of-range integers) before constructing a `kill` command.
    static func validatedTargetPID(_ raw: Int?) throws(MCPError) -> Int32? {
        guard let raw else { return nil }
        guard let pid = Int32(exactly: raw) else {
            throw .invalidParams("pid \(raw) is out of range for a process identifier.")
        }
        guard pid > 1 else {
            throw .invalidParams(
                "Refusing to signal PID \(pid): values ≤ 1 address process groups or system processes.",
            )
        }
        return pid
    }

    /// Resolves a bundle id / app name to exact PIDs via NSRunningApplication, NSWorkspace, and any
    /// active LLDB session. Returns the de-duplicated set of matching PIDs (empty if none running).
    private func resolvePIDs(bundleId: String?, appName: String?) async -> [Int32] {
        var pids = Set<Int32>()
        if let bundleId {
            if let pid = await PIDResolver.findPID(forBundleID: bundleId) { pids.insert(pid) }
            if let pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId) {
                pids.insert(pid)
            }
        }
        if let appName {
            for pid in await PIDResolver.findPIDs(forAppName: appName) { pids.insert(pid) }
        }
        return Array(pids)
    }

    /// Builds the standard "not running" result for the given identifier.
    static func notRunning(_ identifier: String) -> CallTool.Result {
        CallTool.Result(content: [.text(
            text: "App '\(identifier)' was not running",
            annotations: nil,
            _meta: nil,
        )])
    }

    /// Detaches LLDB from a process if it has an active debug session.
    ///
    /// A process traced by LLDB (TX state) cannot be killed by signals — they are
    /// intercepted by the debugger. Detaching releases the traced state so
    /// SIGTERM/SIGKILL can be delivered.
    private func detachDebuggerIfNeeded(pid: Int32) async {
        if let session = await LLDBSessionManager.shared.getSession(pid: pid) {
            _ = try? await session.sendCommand("detach")
            await LLDBSessionManager.shared.removeSession(pid: pid)
        }
    }

    /// Force-kills every resolved PID with SIGKILL.
    private func forceKill(
        pids: [Int32],
        identifier: String,
    ) async throws -> CallTool.Result {
        var killedAny = false
        for pid in pids {
            await detachDebuggerIfNeeded(pid: pid)
            let result = try await ProcessResult.run("/bin/kill", arguments: ["-9", "\(pid)"])
            killedAny = killedAny || result.succeeded
        }
        if killedAny {
            return CallTool.Result(content: [.text(
                text: "Successfully stopped '\(identifier)' (forced)",
                annotations: nil,
                _meta: nil,
            )])
        }
        // Every PID was already gone
        return Self.notRunning(identifier)
    }

    /// Graceful kill when we have a PID: SIGTERM with timeout, then SIGKILL.
    private func gracefulKillByPID(
        pid: Int32,
        identifier: String,
    ) async throws -> CallTool.Result {
        // Detach LLDB first — a traced process (TX state) ignores signals
        await detachDebuggerIfNeeded(pid: pid)

        // Send SIGTERM
        let termResult = try await ProcessResult.run(
            "/bin/kill", arguments: ["-TERM", "\(pid)"],
        )

        if !termResult.succeeded {
            return CallTool.Result(content: [.text(
                text: "App '\(identifier)' was not running",
                annotations: nil,
                _meta: nil,
            )])
        }

        // Wait up to 5 seconds for the process to exit
        if await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(5)) {
            return CallTool.Result(
                content: [.text(
                    text: "Successfully stopped '\(identifier)'",
                    annotations: nil,
                    _meta: nil,
                )],
            )
        }

        // Process didn't exit gracefully — escalate to SIGKILL
        _ = try await ProcessResult.run("/bin/kill", arguments: ["-9", "\(pid)"])
        return CallTool.Result(
            content: [
                .text(
                    text: "Successfully stopped '\(identifier)' (escalated to SIGKILL after timeout)",
                    annotations: nil,
                    _meta: nil,
                ),
            ],
        )
    }

    /// Graceful quit via osascript with a 5-second timeout, escalating to SIGKILL on the resolved
    /// PIDs (never a `pkill -f` pattern) for any survivors.
    ///
    /// `pids` were already resolved by exact match, so the app is known to be running and we target
    /// those exact processes when escalating.
    private func gracefulQuit(
        bundleId: String?,
        appName: String?,
        pids: [Int32],
        identifier: String,
    ) async throws -> CallTool.Result {
        let script: String
        if let bundleId {
            script = "tell application id \"\(bundleId)\" to quit"
        } else if let appName {
            script = "tell application \"\(appName)\" to quit"
        } else {
            throw MCPError.invalidParams("Either bundle_id or app_name is required")
        }

        // Dispatch the Apple Event quit (best effort). If osascript hangs — app is stuck or under a
        // debugger — the timeout fires and we escalate to signals below.
        var quitTimedOut = false
        do {
            _ = try await ProcessResult.run(
                "/usr/bin/osascript",
                arguments: ["-e", script],
                timeout: .seconds(5),
            )
        } catch is ProcessError {
            quitTimedOut = true
        }

        // Wait for each resolved PID to exit; collect any that ignored the quit.
        var survivors: [Int32] = []
        for pid in pids where !(await ProcessResult.waitForProcessExit(pid: pid, timeout: .seconds(5))) {
            survivors.append(pid)
        }

        if survivors.isEmpty {
            let suffix = quitTimedOut ? " (graceful quit timed out)" : ""
            return CallTool.Result(content: [.text(
                text: "Successfully stopped '\(identifier)'\(suffix)",
                annotations: nil,
                _meta: nil,
            )])
        }

        // Escalate to SIGKILL on the exact survivors. Detach LLDB first — traced processes (TX
        // state) intercept signals.
        for pid in survivors {
            await detachDebuggerIfNeeded(pid: pid)
            _ = try await ProcessResult.run("/bin/kill", arguments: ["-9", "\(pid)"])
        }
        return CallTool.Result(content: [.text(
            text: "Successfully stopped '\(identifier)' (graceful quit timed out, used SIGKILL)",
            annotations: nil,
            _meta: nil,
        )])
    }
}
