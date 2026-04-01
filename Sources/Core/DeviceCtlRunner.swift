import MCP
import Foundation
import Subprocess

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

    /// Device platform (e.g., "iOS", "tvOS", "watchOS").
    public let platform: String

    /// Hardware UDID (Apple format, e.g., "00008110-00116D221AA1801E").
    /// Differs from the CoreDevice UUID identifier. Used by libimobiledevice tools.
    public let hardwareUDID: String?

    /// Creates a new connected device instance.
    public init(
        udid: String,
        name: String,
        deviceType: String,
        osVersion: String,
        connectionType: String,
        platform: String = "iOS",
        hardwareUDID: String? = nil,
    ) {
        self.udid = udid
        self.name = name
        self.deviceType = deviceType
        self.osVersion = osVersion
        self.connectionType = connectionType
        self.platform = platform
        self.hardwareUDID = hardwareUDID
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
    public func run(arguments: [String]) async throws(DeviceCtlError) -> DeviceCtlResult {
        do {
            return try await ProcessResult.runSubprocess(
                .name("xcrun"),
                arguments: Arguments(["devicectl"] + arguments),
            )
        } catch {
            throw DeviceCtlError.commandFailed("\(error)")
        }
    }

    /// Lists all connected physical devices.
    ///
    /// - Returns: An array of ``ConnectedDevice`` representing all connected devices.
    /// - Throws: ``DeviceCtlError/commandFailed(_:)`` if the command fails,
    ///   or ``DeviceCtlError/invalidOutput`` if the output cannot be parsed.
    public func listDevices() async throws(DeviceCtlError) -> [ConnectedDevice] {
        let result = try await run(arguments: ["list", "devices", "--json-output", "-"])

        guard result.succeeded else {
            throw DeviceCtlError.commandFailed(result.stderr)
        }

        // Parse the JSON output
        return try parseDeviceList(from: result.stdout)
    }

    /// Looks up a connected device by UDID.
    ///
    /// - Parameter udid: The device UDID to find.
    /// - Returns: The ``ConnectedDevice`` matching the UDID.
    /// - Throws: ``DeviceCtlError/deviceNotFound(_:)`` if no device matches.
    public func lookupDevice(udid: String) async throws(DeviceCtlError) -> ConnectedDevice {
        let devices = try await listDevices()
        guard let device = devices.first(where: { $0.udid == udid }) else {
            throw DeviceCtlError.deviceNotFound(udid)
        }
        return device
    }

    /// Installs an app on a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - appPath: Path to the .app bundle to install.
    /// - Returns: The result containing exit code and output.
    public func install(
        udid: String,
        appPath: String,
    ) async throws(DeviceCtlError) -> DeviceCtlResult {
        try await run(arguments: ["device", "install", "app", "--device", udid, appPath])
    }

    /// Launches an app on a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to launch.
    /// - Returns: The result containing exit code and output.
    public func launch(
        udid: String,
        bundleId: String,
    ) async throws(DeviceCtlError) -> DeviceCtlResult {
        try await run(arguments: ["device", "process", "launch", "--device", udid, bundleId])
    }

    /// Terminates an app on a physical device by resolving its bundle ID to a PID.
    ///
    /// `devicectl device process terminate` requires a `--pid` argument. This method
    /// first queries the device's running processes to find the PID matching the given
    /// bundle identifier, then terminates that process.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to terminate.
    /// - Returns: The result containing exit code and output.
    /// - Throws: ``DeviceCtlError/processNotFound(_:)`` if no running process matches.
    public func terminate(
        udid: String,
        bundleId: String,
    ) async throws(DeviceCtlError) -> DeviceCtlResult {
        let pid = try await findPID(forBundleID: bundleId, udid: udid)
        return try await run(arguments: [
            "device", "process", "terminate", "--device", udid, "--pid", "\(pid)",
        ])
    }

    /// Lists running processes on a physical device.
    ///
    /// - Parameter udid: The UDID of the target device.
    /// - Returns: An array of ``DeviceProcess`` representing running processes.
    public func listProcesses(udid: String) async throws(DeviceCtlError) -> [DeviceProcess] {
        let result = try await run(arguments: [
            "device", "info", "processes", "--device", udid, "--json-output", "-",
        ])
        guard result.succeeded else {
            throw DeviceCtlError.commandFailed(result.stderr)
        }
        return try parseProcessList(from: result.stdout)
    }

    /// Finds the PID of a running app on a device by its bundle identifier.
    ///
    /// Queries the device's running processes and matches by bundle URL or executable
    /// path against the bundle identifier.
    ///
    /// - Parameters:
    ///   - bundleId: The bundle identifier to look for.
    ///   - udid: The UDID of the target device.
    /// - Returns: The PID of the matching process.
    /// - Throws: ``DeviceCtlError/processNotFound(_:)`` if no match is found.
    public func findPID(
        forBundleID bundleId: String,
        udid: String,
    ) async throws(DeviceCtlError) -> Int {
        let processes = try await listProcesses(udid: udid)
        // Try exact bundle URL match first (e.g. ".../com.example.MyApp/...")
        if let match = processes.first(where: { $0.bundleURL?.contains(bundleId) == true }) {
            return match.processIdentifier
        }
        // Fall back to executable path matching the last component of the bundle ID
        let appName = bundleId.components(separatedBy: ".").last ?? bundleId
        if let match = processes.first(where: {
            $0.executable?.localizedCaseInsensitiveContains(appName) == true
        }) {
            return match.processIdentifier
        }
        throw DeviceCtlError.processNotFound(bundleId)
    }

    /// Gets app information from a physical device.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target device.
    ///   - bundleId: Bundle identifier of the app to query.
    /// - Returns: The result containing JSON-formatted app information.
    public func getAppInfo(
        udid: String,
        bundleId: String,
    ) async throws(DeviceCtlError) -> DeviceCtlResult {
        try await run(arguments: [
            "device", "info", "apps", "--device", udid, "--bundle-id", bundleId, "--json-output",
            "-",
        ])
    }

    private static let decoder = JSONDecoder()

    private func parseProcessList(from jsonString: String) throws(DeviceCtlError)
        -> [DeviceProcess]
    {
        guard let data = jsonString.data(using: .utf8) else {
            throw DeviceCtlError.invalidOutput
        }
        do {
            let response = try Self.decoder.decode(
                DeviceCtlResponse<ProcessListResult>.self,
                from: data,
            )
            return response.result.runningProcesses.compactMap { process in
                guard let pid = process.processIdentifier else { return nil }
                return DeviceProcess(
                    processIdentifier: pid,
                    executable: process.executable,
                    bundleURL: process.bundleURL,
                )
            }
        } catch {
            throw DeviceCtlError.invalidOutput
        }
    }

    private func parseDeviceList(from jsonString: String) throws(DeviceCtlError)
        -> [ConnectedDevice]
    {
        guard let data = jsonString.data(using: .utf8) else {
            throw DeviceCtlError.invalidOutput
        }
        do {
            let response = try Self.decoder.decode(
                DeviceCtlResponse<DeviceListResult>.self,
                from: data,
            )
            return response.result.devices.compactMap { device in
                guard let name = device.deviceProperties?.name,
                      let connectionProperties = device.connectionProperties
                else { return nil }

                let hw = device.hardwareProperties
                let deviceType =
                    hw?.marketingName ?? hw?.productType ?? hw?.deviceType ?? "Unknown"

                return ConnectedDevice(
                    udid: device.identifier,
                    name: name,
                    deviceType: deviceType,
                    osVersion: device.deviceProperties?.osVersionNumber ?? "Unknown",
                    connectionType: connectionProperties.transportType ?? "Unknown",
                    platform: hw?.platform ?? "iOS",
                    hardwareUDID: hw?.udid,
                )
            }
        } catch {
            throw DeviceCtlError.invalidOutput
        }
    }
}

// MARK: - devicectl JSON Response Types

private struct DeviceCtlResponse<T: Decodable & Sendable>: Decodable {
    let result: T
}

private struct ProcessListResult: Decodable {
    let runningProcesses: [ProcessEntry]
}

private struct ProcessEntry: Decodable {
    let processIdentifier: Int?
    let executable: String?
    let bundleURL: String?
}

private struct DeviceListResult: Decodable {
    let devices: [DeviceEntry]
}

private struct DeviceEntry: Decodable {
    let identifier: String
    let deviceProperties: DeviceProperties?
    let hardwareProperties: HardwareProperties?
    let connectionProperties: ConnectionProperties?
}

private struct DeviceProperties: Decodable {
    let name: String?
    let osVersionNumber: String?
}

private struct HardwareProperties: Decodable {
    let marketingName: String?
    let productType: String?
    let deviceType: String?
    let platform: String?
    let udid: String?
}

private struct ConnectionProperties: Decodable {
    let transportType: String?
}

/// A running process on a physical device.
public struct DeviceProcess: Sendable {
    /// The process identifier (PID).
    public let processIdentifier: Int

    /// The executable path, if available.
    public let executable: String?

    /// The bundle URL, if available.
    public let bundleURL: String?
}

/// Errors that can occur during devicectl operations.
public enum DeviceCtlError: LocalizedError, Sendable, MCPErrorConvertible {
    /// A devicectl command failed with an error message.
    case commandFailed(String)

    /// The output from devicectl could not be parsed.
    case invalidOutput

    /// The specified device was not found.
    case deviceNotFound(String)

    /// No running process found matching the bundle identifier.
    case processNotFound(String)

    public var errorDescription: String? {
        switch self {
            case let .commandFailed(message):
                return "devicectl command failed: \(message)"
            case .invalidOutput:
                return "devicectl returned invalid output"
            case let .deviceNotFound(udid):
                return "Device not found: \(udid)"
            case let .processNotFound(bundleId):
                return "No running process found for bundle identifier: \(bundleId)"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case .deviceNotFound:
                return .invalidParams(errorDescription ?? "Device not found")
            case .processNotFound:
                return .invalidParams(errorDescription ?? "Process not found")
            case .commandFailed, .invalidOutput:
                return .internalError(errorDescription ?? "Device operation failed")
        }
    }
}
