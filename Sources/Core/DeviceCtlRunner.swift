import Foundation

/// Information about a connected physical device.
///
/// Represents a physical iOS, tvOS, or watchOS device connected to the Mac.
public struct ConnectedDevice: Sendable {
    /// Unique device identifier (UDID).
    public let udid: String

    /// Human-readable device name.
    public let name: String

    /// Device model type (e.g., "iPhone15,2").
    public let deviceType: String

    /// Operating system version (e.g., "17.0").
    public let osVersion: String

    /// Connection type ("usb" or "network").
    public let connectionType: String

    /// Creates a new connected device instance.
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

/// Wrapper for executing devicectl commands.
///
/// `DeviceCtlRunner` provides a Swift interface for invoking Xcode's device
/// control tool. It supports listing connected devices, installing apps, and
/// launching/terminating processes on physical devices.
///
/// ## Example
///
/// ```swift
/// let runner = DeviceCtlRunner()
///
/// // List connected devices
/// let devices = try await runner.listDevices()
///
/// // Install an app
/// try await runner.install(udid: device.udid, appPath: "/path/to/App.app")
///
/// // Launch the app
/// try await runner.launch(udid: device.udid, bundleId: "com.example.app")
/// ```
public struct DeviceCtlRunner: Sendable {
    /// Creates a new devicectl runner.
    public init() {}

    /// Executes a devicectl command with the given arguments.
    ///
    /// - Parameter arguments: The command-line arguments to pass to devicectl.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
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

    /// Lists all connected physical devices.
    ///
    /// - Returns: An array of ``ConnectedDevice`` representing all connected devices.
    /// - Throws: ``DeviceCtlError/commandFailed(_:)`` if the command fails,
    ///   or ``DeviceCtlError/invalidOutput`` if the output cannot be parsed.
    public func listDevices() async throws -> [ConnectedDevice] {
        let result = try await run(arguments: ["list", "devices", "--json-output", "-"])

        guard result.succeeded else {
            throw DeviceCtlError.commandFailed(result.stderr)
        }

        // Parse the JSON output
        return try parseDeviceList(from: result.stdout)
    }

    /// Installs an app on a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - appPath: Path to the .app bundle to install.
    /// - Returns: The result containing exit code and output.
    public func install(udid: String, appPath: String) async throws -> DeviceCtlResult {
        try await run(arguments: ["device", "install", "app", "--device", udid, appPath])
    }

    /// Launches an app on a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to launch.
    /// - Returns: The result containing exit code and output.
    public func launch(udid: String, bundleId: String) async throws -> DeviceCtlResult {
        try await run(arguments: ["device", "process", "launch", "--device", udid, bundleId])
    }

    /// Terminates an app on a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to terminate.
    /// - Returns: The result containing exit code and output.
    public func terminate(udid: String, bundleId: String) async throws -> DeviceCtlResult {
        try await run(arguments: [
            "device", "process", "terminate", "--device", udid, "--bundle-id", bundleId,
        ])
    }

    /// Gets app information from a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to query.
    /// - Returns: The result containing JSON-formatted app information.
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

/// Errors that can occur during devicectl operations.
public enum DeviceCtlError: LocalizedError, Sendable {
    /// A devicectl command failed with an error message.
    case commandFailed(String)

    /// The output from devicectl could not be parsed.
    case invalidOutput

    /// The specified device was not found.
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
