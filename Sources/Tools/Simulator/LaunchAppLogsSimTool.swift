import Foundation
import MCP

public struct LaunchAppLogsSimTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "launch_app_logs_sim",
            description:
                "Launch an app on a simulator and capture its console output (stdout/stderr) for a specified duration.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to launch (e.g., 'com.example.MyApp')."
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "duration_seconds": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of seconds to capture logs. Defaults to 10 seconds. Max 60 seconds."
                        ),
                    ]),
                    "args": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional arguments to pass to the app."),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(bundleId) = arguments["bundle_id"] else {
            throw MCPError.invalidParams("bundle_id is required")
        }

        // Get simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly.")
        }

        var durationSeconds: Int = 10
        if case let .int(value) = arguments["duration_seconds"] {
            durationSeconds = min(60, max(1, value))
        }

        var launchArgs: [String] = []
        if case let .array(argsArray) = arguments["args"] {
            for arg in argsArray {
                if case let .string(argValue) = arg {
                    launchArgs.append(argValue)
                }
            }
        }

        do {
            // Launch the app with console output redirection
            // Using simctl spawn with the app
            let launchResult = try await simctlRunner.launch(
                udid: simulator,
                bundleId: bundleId,
                waitForDebugger: false,
                args: launchArgs
            )

            guard launchResult.succeeded else {
                throw MCPError.internalError(
                    "Failed to launch app: \(launchResult.stderr.isEmpty ? launchResult.stdout : launchResult.stderr)"
                )
            }

            // Extract PID for log filtering
            let pid = extractPID(from: launchResult.stdout)

            // Capture logs using log stream
            let logs = try await captureLogs(
                simulator: simulator,
                bundleId: bundleId,
                pid: pid,
                duration: durationSeconds
            )

            var output = "Launched '\(bundleId)' on simulator '\(simulator)'\n"
            if let pid {
                output += "Process ID: \(pid)\n"
            }
            output += "Captured \(durationSeconds) seconds of logs:\n\n"
            output += logs

            return CallTool.Result(content: [.text(output)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to launch app with logs: \(error.localizedDescription)")
        }
    }

    private func extractPID(from output: String) -> String? {
        let components = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ": ")
        if components.count >= 2 {
            return components.last
        }
        return nil
    }

    private func captureLogs(simulator: String, bundleId: String, pid: String?, duration: Int)
        async throws -> String
    {
        // Use log stream to capture logs
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var args = ["simctl", "spawn", simulator, "log", "stream", "--style", "compact"]

        // Filter by subsystem/process if we can
        if let pid {
            args.append(contentsOf: ["--predicate", "processID == \(pid)"])
        } else {
            // Filter by bundle ID subsystem
            args.append(contentsOf: ["--predicate", "subsystem CONTAINS '\(bundleId)'"])
        }

        process.arguments = args

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stdoutPipe

        try process.run()

        // Wait for specified duration
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)

        // Terminate log stream
        process.terminate()

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Limit output size
        let lines = output.components(separatedBy: .newlines)
        if lines.count > 200 {
            return lines.suffix(200).joined(separator: "\n")
                + "\n\n(Output truncated to last 200 lines)"
        }

        return output
    }
}
