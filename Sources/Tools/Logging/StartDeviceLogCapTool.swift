import MCP
import XCMCPCore
import Foundation

public struct StartDeviceLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner _: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager,
    ) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_device_log_cap",
            description:
            "Start capturing logs related to a physical device. Streams logs in real-time using `log stream` and writes them to a file. Use stop_device_log_cap to stop and retrieve the captured logs.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID. Uses session default if not specified.",
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write filtered logs to. Defaults to /tmp/device_log_<udid>.log",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app's process.",
                        ),
                    ]),
                    "subsystem": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional OSLog subsystem to filter logs (e.g., 'com.example.myapp').",
                        ),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional NSPredicate to filter logs. Overrides bundle_id and subsystem filters.",
                        ),
                    ]),
                    "level": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Log level: 'default', 'info', or 'debug'. Default is 'default'.",
                        ),
                        "enum": .array([
                            .string("default"),
                            .string("info"),
                            .string("debug"),
                        ]),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let device = try await sessionManager.resolveDevice(from: arguments)
        let outputFile = arguments.getString("output_file")
            ?? "/tmp/device_log_\(device).log"
        let bundleId = arguments.getString("bundle_id")
        let subsystem = arguments.getString("subsystem")
        let customPredicate = arguments.getString("predicate")
        let level = arguments.getString("level")

        // Build the predicate
        let predicate: String?
        if let customPredicate {
            predicate = customPredicate
        } else {
            var parts: [String] = []
            if let bundleId {
                let appName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
                parts.append("process ==[cd] \"\(appName)\"")
            }
            if let subsystem {
                parts.append("subsystem == \"\(subsystem)\"")
            }
            predicate = parts.isEmpty ? nil : parts.joined(separator: " AND ")
        }

        do {
            var args = ["stream", "--device-udid", device, "--style", "compact"]

            // Add log level flags
            if let level {
                switch level {
                    case "debug":
                        args.append("--debug")
                    case "info":
                        args.append("--info")
                    default:
                        break
                }
            }

            if let predicate {
                args.append(contentsOf: ["--predicate", predicate])
            }

            let pid = try LogCapture.launchStreamProcess(
                executable: "/usr/bin/log", arguments: args, outputFile: outputFile,
            )

            // Verify the log stream process is still running after a brief delay
            try await LogCapture.verifyStreamHealth(pid: pid, outputFile: outputFile)

            // Save capture metadata so stop_device_log_cap can find the process
            let metadata = DeviceLogCapMetadata(
                device: device,
                pid: pid,
                outputFile: outputFile,
            )
            let metadataPath = DeviceLogCapMetadata.path(for: device)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(metadata)
            FileManager.default.createFile(atPath: metadataPath, contents: data)

            var message = "Started log capture for device '\(device)'\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let predicate {
                message += "Predicate: \(predicate)\n"
            }
            if let level, level != "default" {
                message += "Level: \(level)\n"
            }
            message += "\nUse stop_device_log_cap to stop the capture and retrieve logs."

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}

/// Metadata saved by start_device_log_cap for stop_device_log_cap to consume.
struct DeviceLogCapMetadata: Codable {
    let device: String
    let pid: Int32
    let outputFile: String

    static func path(for device: String) -> String {
        "/tmp/device_log_cap_\(device).json"
    }
}
