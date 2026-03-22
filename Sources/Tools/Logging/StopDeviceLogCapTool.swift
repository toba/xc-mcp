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
            "Stop capturing device logs and return the captured output. Kills the log stream process started by start_device_log_cap and returns the last N lines of the log file.",
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
                            "Path to the log file to return the last N lines from. Overrides the path from start_device_log_cap.",
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

        // Stop the stream process
        await LogCapture.stopCapture(
            pid: Int(metadata.pid),
            pkillPatterns: [],
        )

        // Clean up metadata file
        try? FileManager.default.removeItem(atPath: metadataPath)

        var message = "Stopped log capture for device '\(device)'\n"
        message += "Output file: \(outputFile)"

        await LogCapture.appendTail(to: &message, from: outputFile, lines: tailLines)

        return CallTool.Result(content: [.text(message)])
    }
}
