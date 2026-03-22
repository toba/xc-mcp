import MCP
import XCMCPCore
import Foundation

public struct StartDeviceLogCapTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager,
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_device_log_cap",
            description:
            "Start capturing logs from a physical device in real-time using idevicesyslog (libimobiledevice). Streams device unified logs over USB. Filter by string match or process name. Requires `brew install libimobiledevice`. Use stop_device_log_cap to stop and retrieve the captured logs.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID (CoreDevice or hardware format). Uses session default if not specified.",
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write filtered logs to. Defaults to /tmp/device_log_<udid>.log",
                        ),
                    ]),
                    "match": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only capture lines containing this string (e.g., subsystem name like 'app.toba.myapp'). Maps to idevicesyslog -m.",
                        ),
                    ]),
                    "process": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only capture lines from this process name. Maps to idevicesyslog -p.",
                        ),
                    ]),
                    "quiet": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Exclude common noisy system processes. Default: true.",
                        ),
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
        let match = arguments.getString("match")
        let process = arguments.getString("process")
        let quiet: Bool
        if case let .bool(q) = arguments["quiet"] {
            quiet = q
        } else {
            quiet = true
        }

        do {
            let idevicesyslog = try await findIdevicesyslog()

            // Resolve hardware UDID — idevicesyslog uses Apple hardware UDIDs,
            // not CoreDevice UUIDs
            let hwUDID = try await resolveHardwareUDID(coreDeviceUDID: device)

            var args = ["-u", hwUDID, "-x", "--no-colors"]
            if quiet {
                args.append("-q")
            }
            if let match {
                args.append(contentsOf: ["-m", match])
            }
            if let process {
                args.append(contentsOf: ["-p", process])
            }

            let pid = try LogCapture.launchStreamProcess(
                executable: idevicesyslog, arguments: args, outputFile: outputFile,
            )

            // Verify the process is still running after a brief delay
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
            message += "Backend: idevicesyslog (hardware UDID: \(hwUDID))\n"
            if let match {
                message += "Match filter: \(match)\n"
            }
            if let process {
                message += "Process filter: \(process)\n"
            }
            message += "\nUse stop_device_log_cap to stop the capture and retrieve logs."

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }

    /// Resolves a CoreDevice UUID to the Apple hardware UDID that idevicesyslog expects.
    /// If the input is already a hardware UDID (not UUID format), returns it as-is.
    private func resolveHardwareUDID(coreDeviceUDID: String) async throws -> String {
        // Hardware UDIDs are hex strings like "00008110-00116D221AA1801E"
        // CoreDevice UUIDs are standard UUIDs like "A5CC2917-0B66-5306-8C9F-A60BFEB112C1"
        // Heuristic: CoreDevice UUIDs have 5 groups (8-4-4-4-12), hardware UDIDs have 2 groups (8-16)
        let parts = coreDeviceUDID.split(separator: "-")
        if parts.count == 2 {
            // Already looks like a hardware UDID
            return coreDeviceUDID
        }

        // Look up via devicectl
        let device = try await deviceCtlRunner.lookupDevice(udid: coreDeviceUDID)
        guard let hwUDID = device.hardwareUDID else {
            throw MCPError.internalError(
                "Could not resolve hardware UDID for device '\(coreDeviceUDID)'. "
                    + "Try passing the hardware UDID directly (visible via `idevice_id -l`).",
            )
        }
        return hwUDID
    }

    private func findIdevicesyslog() async throws(MCPError) -> String {
        for path in ["/opt/homebrew/bin/idevicesyslog", "/usr/local/bin/idevicesyslog"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        do {
            return try await BinaryLocator.find("idevicesyslog")
        } catch {
            throw MCPError.internalError(
                "idevicesyslog not found. Install it with: brew install libimobiledevice",
            )
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
