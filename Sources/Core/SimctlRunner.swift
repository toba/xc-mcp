import MCP
import Foundation

/// Information about a simulator device.
///
/// Represents a simulator instance with its identification, state, and runtime information.
public struct SimulatorDevice: Sendable, Codable {
    /// Unique device identifier (UDID) for the simulator.
    public let udid: String

    /// Human-readable name of the simulator (e.g., "iPhone 15 Pro").
    public let name: String

    /// Current state of the simulator (e.g., "Booted", "Shutdown").
    public let state: String

    /// Whether the simulator runtime is available on the system.
    public let isAvailable: Bool

    /// The device type identifier (e.g., "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro").
    public let deviceTypeIdentifier: String?

    /// The runtime identifier (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-17-0").
    public let runtime: String?

    enum CodingKeys: String, CodingKey {
        case udid
        case name
        case state
        case isAvailable
        case deviceTypeIdentifier
        case runtime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        udid = try container.decode(String.self, forKey: .udid)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
        deviceTypeIdentifier = try container.decodeIfPresent(
            String.self, forKey: .deviceTypeIdentifier,
        )
        runtime = nil // Runtime comes from the parent key, not the device object
    }

    public init(
        udid: String,
        name: String,
        state: String,
        isAvailable: Bool,
        deviceTypeIdentifier: String?,
        runtime: String?,
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtime = runtime
    }
}

/// Response structure from simctl list devices -j command.
struct SimctlDevicesResponse: Codable {
    let devices: [String: [SimulatorDevice]]
}

/// Wrapper for executing simctl commands.
///
/// `SimctlRunner` provides a Swift interface for invoking the iOS Simulator
/// control tool. It supports listing, booting, and managing simulators,
/// as well as installing and launching apps.
///
/// ## Example
///
/// ```swift
/// let runner = SimctlRunner()
///
/// // List all simulators
/// let devices = try await runner.listDevices()
///
/// // Boot a simulator
/// try await runner.boot(udid: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")
///
/// // Launch an app
/// try await runner.launch(udid: udid, bundleId: "com.example.app")
/// ```
public struct SimctlRunner: Sendable {
    /// Creates a new simctl runner.
    public init() {}

    /// Executes a simctl command with the given arguments.
    ///
    /// - Parameter arguments: The command-line arguments to pass to simctl.
    /// - Returns: The result containing exit code and output.
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String]) async throws -> SimctlResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()

                let pipes = ProcessResult.drainPipes(stdout: stdoutPipe, stderr: stderrPipe)
                process.waitUntilExit()

                let stdout = String(data: pipes.stdout, encoding: .utf8) ?? ""
                let stderr = String(data: pipes.stderr, encoding: .utf8) ?? ""

                let result = SimctlResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr,
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Lists all available simulator devices.
    ///
    /// - Returns: An array of ``SimulatorDevice`` representing all available simulators.
    /// - Throws: ``SimctlError/commandFailed(_:)`` if the command fails,
    ///   or ``SimctlError/invalidOutput`` if the output cannot be parsed.
    public func listDevices() async throws -> [SimulatorDevice] {
        let result = try await run(arguments: ["list", "devices", "-j"])

        guard result.succeeded else {
            throw SimctlError.commandFailed(result.stderr)
        }

        guard let data = result.stdout.data(using: .utf8) else {
            throw SimctlError.invalidOutput
        }

        let response = try JSONDecoder().decode(SimctlDevicesResponse.self, from: data)

        // Flatten the devices dictionary and add runtime info
        var devices: [SimulatorDevice] = []
        for (runtime, runtimeDevices) in response.devices {
            for device in runtimeDevices {
                let deviceWithRuntime = SimulatorDevice(
                    udid: device.udid,
                    name: device.name,
                    state: device.state,
                    isAvailable: device.isAvailable,
                    deviceTypeIdentifier: device.deviceTypeIdentifier,
                    runtime: runtime,
                )
                devices.append(deviceWithRuntime)
            }
        }

        return devices
    }

    /// Boots a simulator.
    ///
    /// - Parameter udid: The UDID of the simulator to boot.
    /// - Returns: The result containing exit code and output.
    public func boot(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["boot", udid])
    }

    /// Shuts down a simulator.
    ///
    /// - Parameter udid: The UDID of the simulator to shut down.
    /// - Returns: The result containing exit code and output.
    public func shutdown(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["shutdown", udid])
    }

    /// Erases a simulator, resetting it to factory state.
    ///
    /// - Parameter udid: The UDID of the simulator to erase.
    /// - Returns: The result containing exit code and output.
    public func erase(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["erase", udid])
    }

    /// Erases all simulators.
    ///
    /// - Returns: The result containing exit code and output.
    public func eraseAll() async throws -> SimctlResult {
        try await run(arguments: ["erase", "all"])
    }

    /// Installs an app on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - appPath: Path to the .app bundle to install.
    /// - Returns: The result containing exit code and output.
    public func install(udid: String, appPath: String) async throws -> SimctlResult {
        try await run(arguments: ["install", udid, appPath])
    }

    /// Uninstalls an app from a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - bundleId: Bundle identifier of the app to uninstall.
    /// - Returns: The result containing exit code and output.
    public func uninstall(udid: String, bundleId: String) async throws -> SimctlResult {
        try await run(arguments: ["uninstall", udid, bundleId])
    }

    /// Launches an app on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - bundleId: Bundle identifier of the app to launch.
    ///   - waitForDebugger: If true, the app waits for a debugger to attach before starting.
    ///   - args: Additional arguments to pass to the app.
    /// - Returns: The result containing exit code and output.
    public func launch(
        udid: String,
        bundleId: String,
        waitForDebugger: Bool = false,
        args: [String] = [],
    ) async throws -> SimctlResult {
        var arguments = ["launch"]
        if waitForDebugger {
            arguments.append("-w")
        }
        arguments.append(udid)
        arguments.append(bundleId)
        arguments.append(contentsOf: args)
        return try await run(arguments: arguments)
    }

    /// Terminates an app on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - bundleId: Bundle identifier of the app to terminate.
    /// - Returns: The result containing exit code and output.
    public func terminate(udid: String, bundleId: String) async throws -> SimctlResult {
        try await run(arguments: ["terminate", udid, bundleId])
    }

    /// Gets the app container path on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - bundleId: Bundle identifier of the app.
    ///   - container: Container type ("app", "data", "groups"). Defaults to "app".
    /// - Returns: The path to the app container.
    /// - Throws: ``SimctlError/commandFailed(_:)`` if the command fails.
    public func getAppContainer(
        udid: String,
        bundleId: String,
        container: String = "app",
    ) async throws -> String {
        let result = try await run(arguments: ["get_app_container", udid, bundleId, container])
        guard result.succeeded else {
            throw SimctlError.commandFailed(result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Opens a URL on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - url: The URL to open.
    /// - Returns: The result containing exit code and output.
    public func openURL(udid: String, url: String) async throws -> SimctlResult {
        try await run(arguments: ["openurl", udid, url])
    }

    /// Takes a screenshot of a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - outputPath: Path where the screenshot will be saved.
    /// - Returns: The result containing exit code and output.
    public func screenshot(udid: String, outputPath: String) async throws -> SimctlResult {
        try await run(arguments: ["io", udid, "screenshot", outputPath])
    }

    /// Starts recording video of a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - outputPath: Path where the video will be saved.
    /// - Returns: The recording process (send SIGINT to stop recording).
    /// - Throws: An error if the process fails to start.
    public func recordVideo(udid: String, outputPath: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "recordVideo", outputPath]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        return process
    }

    /// Sets the simulated location on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - latitude: The latitude coordinate.
    ///   - longitude: The longitude coordinate.
    /// - Returns: The result containing exit code and output.
    public func setLocation(udid: String, latitude: Double, longitude: Double) async throws
        -> SimctlResult
    {
        try await run(arguments: ["location", udid, "set", "\(latitude),\(longitude)"])
    }

    /// Clears the simulated location on a simulator.
    ///
    /// - Parameter udid: The UDID of the target simulator.
    /// - Returns: The result containing exit code and output.
    public func clearLocation(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["location", udid, "clear"])
    }

    /// Sets the appearance mode (dark/light) on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - appearance: The appearance mode ("dark" or "light").
    /// - Returns: The result containing exit code and output.
    public func setAppearance(udid: String, appearance: String) async throws -> SimctlResult {
        try await run(arguments: ["ui", udid, "appearance", appearance])
    }

    /// Overrides status bar values on a simulator.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - time: Custom time to display.
    ///   - batteryLevel: Battery percentage (0-100).
    ///   - batteryState: Battery state ("charging", "charged", "discharging").
    ///   - cellularBars: Number of cellular signal bars (0-4).
    ///   - wifiBars: Number of WiFi signal bars (0-3).
    /// - Returns: The result containing exit code and output.
    public func setStatusBar(
        udid: String,
        time: String? = nil,
        batteryLevel: Int? = nil,
        batteryState: String? = nil,
        cellularBars: Int? = nil,
        wifiBars: Int? = nil,
    ) async throws -> SimctlResult {
        var arguments = ["status_bar", udid, "override"]

        if let time {
            arguments.append(contentsOf: ["--time", time])
        }
        if let batteryLevel {
            arguments.append(contentsOf: ["--batteryLevel", String(batteryLevel)])
        }
        if let batteryState {
            arguments.append(contentsOf: ["--batteryState", batteryState])
        }
        if let cellularBars {
            arguments.append(contentsOf: ["--cellularBars", String(cellularBars)])
        }
        if let wifiBars {
            arguments.append(contentsOf: ["--wifiBars", String(wifiBars)])
        }

        return try await run(arguments: arguments)
    }

    /// Clears all status bar overrides on a simulator.
    ///
    /// - Parameter udid: The UDID of the target simulator.
    /// - Returns: The result containing exit code and output.
    public func clearStatusBar(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["status_bar", udid, "clear"])
    }

    /// Overrides status bar values using a dictionary of options.
    ///
    /// - Parameters:
    ///   - udid: The UDID of the target simulator.
    ///   - options: Dictionary of status bar options to set.
    /// - Returns: The result containing exit code and output.
    public func overrideStatusBar(udid: String, options: [String: Any]) async throws -> SimctlResult
    {
        var arguments = ["status_bar", udid, "override"]

        if let time = options["time"] as? String {
            arguments.append(contentsOf: ["--time", time])
        }
        if let batteryLevel = options["batteryLevel"] as? Int {
            arguments.append(contentsOf: ["--batteryLevel", String(batteryLevel)])
        }
        if let batteryState = options["batteryState"] as? String {
            arguments.append(contentsOf: ["--batteryState", batteryState])
        }
        if let cellularMode = options["cellularMode"] as? String {
            arguments.append(contentsOf: ["--cellularMode", cellularMode])
        }
        if let cellularBars = options["cellularBars"] as? Int {
            arguments.append(contentsOf: ["--cellularBars", String(cellularBars)])
        }
        if let wifiMode = options["wifiMode"] as? String {
            arguments.append(contentsOf: ["--wifiMode", wifiMode])
        }
        if let wifiBars = options["wifiBars"] as? Int {
            arguments.append(contentsOf: ["--wifiBars", String(wifiBars)])
        }

        return try await run(arguments: arguments)
    }
}

/// Errors that can occur during simctl operations.
public enum SimctlError: LocalizedError, Sendable, MCPErrorConvertible {
    /// A simctl command failed with an error message.
    case commandFailed(String)

    /// The output from simctl could not be parsed.
    case invalidOutput

    /// The specified simulator device was not found.
    case deviceNotFound(String)

    public var errorDescription: String? {
        switch self {
            case let .commandFailed(message):
                return "simctl command failed: \(message)"
            case .invalidOutput:
                return "simctl returned invalid output"
            case let .deviceNotFound(udid):
                return "Simulator device not found: \(udid)"
        }
    }

    public func toMCPError() -> MCPError {
        switch self {
            case .deviceNotFound:
                return .invalidParams(errorDescription ?? "Simulator not found")
            case .commandFailed, .invalidOutput:
                return .internalError(errorDescription ?? "Simulator operation failed")
        }
    }
}
