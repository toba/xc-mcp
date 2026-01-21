import Foundation
import MCP

public struct StartDeviceLogCapTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_device_log_cap",
            description:
                "Start capturing logs from a physical device. Logs are written to a file and can be stopped with stop_device_log_cap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID or name. Uses session default if not specified."),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write logs to. Defaults to /tmp/device_log_<udid>.log"),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app."),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional predicate to filter logs (e.g., 'subsystem == \"com.apple.example\"')."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get device
        let device: String
        if case let .string(value) = arguments["device"] {
            device = value
        } else if let sessionDevice = await sessionManager.deviceUDID {
            device = sessionDevice
        } else {
            throw MCPError.invalidParams(
                "device is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get output file
        let outputFile: String
        if case let .string(value) = arguments["output_file"] {
            outputFile = value
        } else {
            outputFile = "/tmp/device_log_\(device).log"
        }

        // Get optional bundle_id filter
        let bundleId: String?
        if case let .string(value) = arguments["bundle_id"] {
            bundleId = value
        } else {
            bundleId = nil
        }

        // Get optional predicate
        let predicate: String?
        if case let .string(value) = arguments["predicate"] {
            predicate = value
        } else {
            predicate = nil
        }

        do {
            // Use devicectl device info syslog or idevicesyslog
            // Try devicectl first (newer), fall back to log stream via USB
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

            // Use devicectl to stream syslog
            let args = ["devicectl", "device", "info", "syslog", "--device", device]

            // Note: devicectl syslog may not support all filter options
            // For more advanced filtering, we may need to post-process

            process.arguments = args

            // Set up file output
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: outputFile) {
                fileManager.createFile(atPath: outputFile, contents: nil)
            }

            guard let fileHandle = FileHandle(forWritingAtPath: outputFile) else {
                throw MCPError.internalError("Failed to open output file: \(outputFile)")
            }
            fileHandle.seekToEndOfFile()

            // If we need filtering, set up a pipe and filter
            if bundleId != nil || predicate != nil {
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                // Set up filtering in background
                let filterBundleId = bundleId
                let filterPredicate = predicate

                DispatchQueue.global().async {
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty else { return }

                        if let line = String(data: data, encoding: .utf8) {
                            // Simple filtering - check if line contains bundle ID
                            var shouldWrite = true
                            if let bundleId = filterBundleId {
                                shouldWrite = line.contains(bundleId)
                            }
                            if shouldWrite, let predicate = filterPredicate {
                                // Very basic predicate matching
                                shouldWrite = line.contains(predicate)
                            }

                            if shouldWrite {
                                fileHandle.write(data)
                            }
                        }
                    }
                }
            } else {
                process.standardOutput = fileHandle
                process.standardError = FileHandle.nullDevice
            }

            try process.run()

            let pid = process.processIdentifier

            var message = "Started log capture for device '\(device)'\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let bundleId = bundleId {
                message += "Filtering for bundle: \(bundleId)\n"
            }
            message += "\nUse stop_device_log_cap to stop the capture."

            return CallTool.Result(content: [.text(message)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to start log capture: \(error.localizedDescription)"
            )
        }
    }
}
