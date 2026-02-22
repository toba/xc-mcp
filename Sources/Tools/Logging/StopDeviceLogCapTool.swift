import MCP
import XCMCPCore
import Foundation

public struct StopDeviceLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_device_log_cap",
            description:
            "Stop capturing logs from a physical device. Can stop by process ID or kill all log capture processes for a device.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the log capture process to stop.",
                        ),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID or name. If specified, stops all log capture for this device.",
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path to the log file to return the last N lines from.",
                        ),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of lines to return from the end of the log file. Defaults to 50.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = arguments.getInt("pid")
        let device: String?
        if let explicit = arguments.getString("device") {
            device = explicit
        } else {
            device = await sessionManager.deviceUDID
        }
        let outputFile =
            arguments.getString("output_file")
                ?? device.map { "/tmp/device_log_\($0).log" }
        let tailLines = arguments.getInt("tail_lines") ?? 50

        // Must have either pid or device
        if pid == nil, device == nil {
            throw MCPError.invalidParams("Either pid or device is required to stop log capture.")
        }

        do {
            if let pid {
                try await ProcessResult.run("/bin/kill", arguments: ["\(pid)"]).ignore()
            } else if let device {
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill",
                    arguments: ["-f", "devicectl.*\(device).*syslog"],
                )
                _ = try? await ProcessResult.run(
                    "/usr/bin/pkill",
                    arguments: ["-f", "devicectl device info syslog.*\(device)"],
                )
            }

            var message = "Stopped log capture"
            if let pid {
                message += " (PID: \(pid))"
            } else if let device {
                message += " for device '\(device)'"
            }

            await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
