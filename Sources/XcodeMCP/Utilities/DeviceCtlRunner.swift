import Foundation

/// Result of a devicectl command execution
public struct DeviceCtlResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }

    public var output: String {
        if stderr.isEmpty {
            return stdout
        } else if stdout.isEmpty {
            return stderr
        } else {
            return stdout + "\n" + stderr
        }
    }
}

/// Information about a connected device
public struct ConnectedDevice: Sendable {
    public let udid: String
    public let name: String
    public let deviceType: String
    public let osVersion: String
    public let connectionType: String

    public init(
        udid: String,
        name: String,
        deviceType: String,
        osVersion: String,
        connectionType: String
    ) {
        self.udid = udid
        self.name = name
        self.deviceType = deviceType
        self.osVersion = osVersion
        self.connectionType = connectionType
    }
}

/// Wrapper for executing devicectl commands
public struct DeviceCtlRunner: Sendable {
    public init() {}

    /// Execute a devicectl command with the given arguments
    public func run(arguments: [String]) async throws -> DeviceCtlResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["devicectl"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = DeviceCtlResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// List all connected devices
    public func listDevices() async throws -> [ConnectedDevice] {
        let result = try await run(arguments: ["list", "devices", "--json-output", "-"])

        guard result.succeeded else {
            throw DeviceCtlError.commandFailed(result.stderr)
        }

        // Parse the JSON output
        return try parseDeviceList(from: result.stdout)
    }

    /// Install an app on a device
    public func install(udid: String, appPath: String) async throws -> DeviceCtlResult {
        try await run(arguments: ["device", "install", "app", "--device", udid, appPath])
    }

    /// Launch an app on a device
    public func launch(udid: String, bundleId: String) async throws -> DeviceCtlResult {
        try await run(arguments: ["device", "process", "launch", "--device", udid, bundleId])
    }

    /// Terminate an app on a device
    public func terminate(udid: String, bundleId: String) async throws -> DeviceCtlResult {
        try await run(arguments: [
            "device", "process", "terminate", "--device", udid, "--bundle-id", bundleId,
        ])
    }

    /// Get app info from a device
    public func getAppInfo(udid: String, bundleId: String) async throws -> DeviceCtlResult {
        try await run(arguments: [
            "device", "info", "apps", "--device", udid, "--bundle-id", bundleId, "--json-output",
            "-",
        ])
    }

    private func parseDeviceList(from jsonString: String) throws -> [ConnectedDevice] {
        guard let data = jsonString.data(using: .utf8) else {
            throw DeviceCtlError.invalidOutput
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = json["result"] as? [String: Any],
            let devices = result["devices"] as? [[String: Any]]
        else {
            throw DeviceCtlError.invalidOutput
        }

        var connectedDevices: [ConnectedDevice] = []

        for device in devices {
            guard
                let identifier = device["identifier"] as? String,
                let deviceProperties = device["deviceProperties"] as? [String: Any],
                let name = deviceProperties["name"] as? String,
                let connectionProperties = device["connectionProperties"] as? [String: Any]
            else {
                continue
            }

            let deviceType =
                (deviceProperties["productType"] as? String)
                ?? (deviceProperties["deviceType"] as? String) ?? "Unknown"
            let osVersion = (deviceProperties["osVersionNumber"] as? String) ?? "Unknown"
            let connectionType = (connectionProperties["transportType"] as? String) ?? "Unknown"

            let connectedDevice = ConnectedDevice(
                udid: identifier,
                name: name,
                deviceType: deviceType,
                osVersion: osVersion,
                connectionType: connectionType
            )
            connectedDevices.append(connectedDevice)
        }

        return connectedDevices
    }
}

/// Errors that can occur during devicectl operations
public enum DeviceCtlError: LocalizedError, Sendable {
    case commandFailed(String)
    case invalidOutput
    case deviceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "devicectl command failed: \(message)"
        case .invalidOutput:
            return "devicectl returned invalid output"
        case .deviceNotFound(let udid):
            return "Device not found: \(udid)"
        }
    }
}
