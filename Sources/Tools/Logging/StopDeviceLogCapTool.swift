import Foundation
import MCP
import XCMCPCore

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
                            "Process ID of the log capture process to stop."),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID or name. If specified, stops all log capture for this device."
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path to the log file to return the last N lines from."),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of lines to return from the end of the log file. Defaults to 50."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid: Int?
        if case let .int(value) = arguments["pid"] {
            pid = value
        } else {
            pid = nil
        }

        let device: String?
        if case let .string(value) = arguments["device"] {
            device = value
        } else {
            device = await sessionManager.deviceUDID
        }

        let outputFile: String?
        if case let .string(value) = arguments["output_file"] {
            outputFile = value
        } else if let dev = device {
            outputFile = "/tmp/device_log_\(dev).log"
        } else {
            outputFile = nil
        }

        let tailLines: Int
        if case let .int(value) = arguments["tail_lines"] {
            tailLines = value
        } else {
            tailLines = 50
        }

        // Must have either pid or device
        if pid == nil && device == nil {
            throw MCPError.invalidParams("Either pid or device is required to stop log capture.")
        }

        do {
            if let pid {
                // Kill specific process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["\(pid)"]

                try process.run()
                process.waitUntilExit()
            } else if let device {
                // Find and kill all devicectl syslog processes for this device
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                process.arguments = ["-f", "devicectl.*\(device).*syslog"]

                try process.run()
                process.waitUntilExit()

                // Also try alternate pattern
                let process2 = Process()
                process2.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                process2.arguments = ["-f", "devicectl device info syslog.*\(device)"]

                try process2.run()
                process2.waitUntilExit()
            }

            var message = "Stopped log capture"
            if let pid {
                message += " (PID: \(pid))"
            } else if let device {
                message += " for device '\(device)'"
            }

            // Read tail of log file if available
            if let outputFile, FileManager.default.fileExists(atPath: outputFile) {
                let tailProcess = Process()
                tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
                tailProcess.arguments = ["-n", "\(tailLines)", outputFile]

                let pipe = Pipe()
                tailProcess.standardOutput = pipe

                try tailProcess.run()
                tailProcess.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let tailOutput = String(data: data, encoding: .utf8), !tailOutput.isEmpty {
                    message += "\n\nLast \(tailLines) lines of log:\n"
                    message += String(repeating: "-", count: 50) + "\n"
                    message += tailOutput
                }
            }

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
