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
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = arguments.getString("bundle_id")
        let appName = arguments.getString("app_name")
        let pid = arguments.getInt("pid").map { Int32($0) }

        if bundleId == nil, appName == nil, pid == nil {
            throw MCPError.invalidParams(
                "At least one of bundle_id, app_name, or pid is required.",
            )
        }

        let force = arguments.getBool("force")
        let identifier = bundleId ?? appName ?? pid.map { "PID \($0)" } ?? "unknown"

        do {
            // If we have a PID (or can resolve one from bundle_id via LLDB session), use signal-based kill
            let resolvedPID: Int32?
            if let pid {
                resolvedPID = pid
            } else {
                resolvedPID = await resolvePID(bundleId: bundleId)
            }

            if force {
                return try await forceKill(
                    pid: resolvedPID, bundleId: bundleId, appName: appName,
                    identifier: identifier,
                )
            }

            // Graceful quit with timeout, then fallback to SIGTERM/SIGKILL
            if let resolvedPID {
                return try await gracefulKillByPID(pid: resolvedPID, identifier: identifier)
            } else {
                return try await gracefulQuitByName(
                    bundleId: bundleId, appName: appName, identifier: identifier,
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }

    /// Resolves a PID from a bundle ID via an active LLDB session.
    private func resolvePID(bundleId: String?) async -> Int32? {
        guard let bundleId else { return nil }
        return await LLDBSessionManager.shared.getPID(bundleId: bundleId)
    }

    /// Force-kills by PID or pkill pattern.
    private func forceKill(
        pid: Int32?,
        bundleId: String?,
        appName: String?,
        identifier: String,
    ) async throws -> CallTool.Result {
        if let pid {
            let result = try await ProcessResult.run(
                "/bin/kill", arguments: ["-9", "\(pid)"],
            )
            if result.succeeded {
                return CallTool.Result(
                    content: [.text("Successfully stopped '\(identifier)' (forced)")],
                )
            }
            // Process may already be gone
            return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
        }

        // Fall back to pkill
        let pattern: String
        if let bundleId {
            pattern = bundleId
        } else if let appName {
            pattern = appName
        } else {
            throw MCPError.invalidParams("Cannot force kill without pid, bundle_id, or app_name")
        }

        let result = try await ProcessResult.run(
            "/usr/bin/pkill",
            arguments: ["-9", "-f", pattern],
        )
        if result.succeeded {
            return CallTool.Result(
                content: [.text("Successfully stopped '\(identifier)' (forced)")],
            )
        }
        return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
    }

    /// Graceful kill when we have a PID: SIGTERM with timeout, then SIGKILL.
    private func gracefulKillByPID(
        pid: Int32,
        identifier: String,
    ) async throws -> CallTool.Result {
        // Send SIGTERM
        let termResult = try await ProcessResult.run(
            "/bin/kill", arguments: ["-TERM", "\(pid)"],
        )

        if !termResult.succeeded {
            return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
        }

        // Wait up to 5 seconds for the process to exit
        if await waitForProcessExit(pid: pid, timeout: .seconds(5)) {
            return CallTool.Result(
                content: [.text("Successfully stopped '\(identifier)'")],
            )
        }

        // Process didn't exit gracefully — escalate to SIGKILL
        _ = try await ProcessResult.run("/bin/kill", arguments: ["-9", "\(pid)"])
        return CallTool.Result(
            content: [
                .text("Successfully stopped '\(identifier)' (escalated to SIGKILL after timeout)"),
            ],
        )
    }

    /// Graceful quit via osascript with a 5-second timeout, falling back to SIGTERM/SIGKILL.
    private func gracefulQuitByName(
        bundleId: String?,
        appName: String?,
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

        // Pre-check: verify the app is actually running before attempting osascript quit.
        // osascript can return success even for non-existent apps on some macOS versions.
        let pattern = bundleId ?? appName!
        let pgrepResult = try await ProcessResult.run(
            "/usr/bin/pgrep", arguments: ["-f", pattern],
        )
        if !pgrepResult.succeeded {
            return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
        }

        do {
            let result = try await ProcessResult.run(
                "/usr/bin/osascript",
                arguments: ["-e", script],
                timeout: .seconds(5),
            )
            if result.succeeded {
                return CallTool.Result(
                    content: [.text("Successfully stopped '\(identifier)'")],
                )
            }
            // App wasn't running
            if result.stdout.isEmpty || result.exitCode == 1 {
                return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
            }
            throw MCPError.internalError("Failed to stop app: \(result.stdout)")
        } catch is ProcessError {
            // osascript timed out — app is hung/crashed/under debugger
            // Fall back to pkill
            let pattern = bundleId ?? appName!
            let termResult = try await ProcessResult.run(
                "/usr/bin/pkill", arguments: ["-TERM", "-f", pattern],
            )
            if !termResult.succeeded {
                return CallTool.Result(content: [.text("App '\(identifier)' was not running")])
            }

            // Give it a moment, then SIGKILL if needed
            try await Task.sleep(for: .seconds(2))
            _ = try await ProcessResult.run(
                "/usr/bin/pkill", arguments: ["-9", "-f", pattern],
            )
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully stopped '\(identifier)' (graceful quit timed out, used SIGTERM/SIGKILL)",
                    ),
                ],
            )
        }
    }

    /// Polls `kill -0` to check if a process is still alive, returning true if it exits within timeout.
    private func waitForProcessExit(pid: Int32, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            // kill -0 checks existence without sending a signal
            let alive = kill(pid, 0) == 0
            if !alive { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }
}
