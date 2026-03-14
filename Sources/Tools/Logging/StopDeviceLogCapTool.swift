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
            "Collect and filter device logs since start_device_log_cap was called. Uses `log collect` to fetch logs from the device, then `log show` to filter with the configured predicate.",
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
                            "Path to write filtered logs to. Overrides the path from start_device_log_cap.",
                        ),
                    ]),
                    "tail_lines": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of lines to return from the end of the log file. Defaults to 100.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let device: String
        if let explicit = arguments.getString("device") {
            device = explicit
        } else if let sessionDevice = await sessionManager.deviceUDID {
            device = sessionDevice
        } else {
            throw MCPError.invalidParams(
                "device is required. Set it with set_session_defaults or pass it directly.",
            )
        }
        let tailLines = arguments.getInt("tail_lines") ?? 100

        // Read metadata from start_device_log_cap
        let metadataPath = DeviceLogCapMetadata.path(for: device)
        guard let metadataData = FileManager.default.contents(atPath: metadataPath),
              let metadata = try? JSONDecoder().decode(
                  DeviceLogCapMetadata.self,
                  from: metadataData,
              )
        else {
            throw MCPError.invalidParams(
                "No active log capture found for device '\(device)'. Call start_device_log_cap first.",
            )
        }

        let outputFile = arguments.getString("output_file") ?? metadata.outputFile
        let archivePath = "/tmp/device_log_\(device).logarchive"

        // Remove any existing archive to avoid conflicts
        try? FileManager.default.removeItem(atPath: archivePath)

        // Collect logs from the device since start time
        var collectArgs = [
            "collect",
            "--device-udid", device,
            "--start", metadata.startTime,
            "--output", archivePath,
        ]
        // Apply predicate at collection time for efficiency
        if let predicate = metadata.predicate {
            collectArgs.append(contentsOf: ["--predicate", predicate])
        }

        let collectResult = try await ProcessResult.run(
            "/usr/bin/log", arguments: collectArgs, timeout: .seconds(60),
        )

        guard collectResult.succeeded else {
            throw MCPError.internalError(
                "Failed to collect device logs: \(collectResult.stderr)",
            )
        }

        // Show logs from the archive with filtering
        var showArgs = [
            "show", archivePath,
            "--style", "compact",
        ]
        if let level = metadata.level {
            switch level {
                case "debug":
                    showArgs.append("--debug")
                case "info":
                    showArgs.append("--info")
                default:
                    break
            }
        }
        if let predicate = metadata.predicate {
            showArgs.append(contentsOf: ["--predicate", predicate])
        }

        let showResult = try await ProcessResult.run(
            "/usr/bin/log", arguments: showArgs, timeout: .seconds(30),
        )

        // Write filtered output to the log file
        if let data = showResult.stdout.data(using: .utf8) {
            FileManager.default.createFile(atPath: outputFile, contents: data)
        }

        // Clean up metadata file
        try? FileManager.default.removeItem(atPath: metadataPath)

        var message = "Collected logs for device '\(device)'\n"
        message += "Time range: \(metadata.startTime) → now\n"
        message += "Output file: \(outputFile)\n"
        message += "Archive: \(archivePath)\n"
        if let predicate = metadata.predicate {
            message += "Predicate: \(predicate)\n"
        }

        await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

        return CallTool.Result(content: [.text(message)])
    }
}
