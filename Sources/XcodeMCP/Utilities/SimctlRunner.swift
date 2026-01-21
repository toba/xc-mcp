import Foundation

/// Result of a simctl command execution
public struct SimctlResult: Sendable {
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

/// Information about a simulator device
public struct SimulatorDevice: Sendable, Codable {
    public let udid: String
    public let name: String
    public let state: String
    public let isAvailable: Bool
    public let deviceTypeIdentifier: String?
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
            String.self, forKey: .deviceTypeIdentifier)
        runtime = nil  // Runtime comes from the parent key, not the device object
    }

    public init(
        udid: String,
        name: String,
        state: String,
        isAvailable: Bool,
        deviceTypeIdentifier: String?,
        runtime: String?
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.deviceTypeIdentifier = deviceTypeIdentifier
        self.runtime = runtime
    }
}

/// Response from simctl list devices -j
struct SimctlDevicesResponse: Codable {
    let devices: [String: [SimulatorDevice]]
}

/// Wrapper for executing simctl commands
public struct SimctlRunner: Sendable {
    public init() {}

    /// Execute a simctl command with the given arguments
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
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = SimctlResult(
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

    /// List all available simulators
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
                    runtime: runtime
                )
                devices.append(deviceWithRuntime)
            }
        }

        return devices
    }

    /// Boot a simulator
    public func boot(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["boot", udid])
    }

    /// Shutdown a simulator
    public func shutdown(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["shutdown", udid])
    }

    /// Erase a simulator
    public func erase(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["erase", udid])
    }

    /// Erase all simulators
    public func eraseAll() async throws -> SimctlResult {
        try await run(arguments: ["erase", "all"])
    }

    /// Install an app on a simulator
    public func install(udid: String, appPath: String) async throws -> SimctlResult {
        try await run(arguments: ["install", udid, appPath])
    }

    /// Uninstall an app from a simulator
    public func uninstall(udid: String, bundleId: String) async throws -> SimctlResult {
        try await run(arguments: ["uninstall", udid, bundleId])
    }

    /// Launch an app on a simulator
    public func launch(
        udid: String,
        bundleId: String,
        waitForDebugger: Bool = false,
        args: [String] = []
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

    /// Terminate an app on a simulator
    public func terminate(udid: String, bundleId: String) async throws -> SimctlResult {
        try await run(arguments: ["terminate", udid, bundleId])
    }

    /// Get the app container path
    public func getAppContainer(
        udid: String,
        bundleId: String,
        container: String = "app"
    ) async throws -> String {
        let result = try await run(arguments: ["get_app_container", udid, bundleId, container])
        guard result.succeeded else {
            throw SimctlError.commandFailed(result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Open a URL on a simulator
    public func openURL(udid: String, url: String) async throws -> SimctlResult {
        try await run(arguments: ["openurl", udid, url])
    }

    /// Take a screenshot
    public func screenshot(udid: String, outputPath: String) async throws -> SimctlResult {
        try await run(arguments: ["io", udid, "screenshot", outputPath])
    }

    /// Start recording video
    public func recordVideo(udid: String, outputPath: String) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "recordVideo", outputPath]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        return process
    }

    /// Set location on a simulator
    public func setLocation(udid: String, latitude: Double, longitude: Double) async throws
        -> SimctlResult
    {
        try await run(arguments: ["location", udid, "set", "\(latitude),\(longitude)"])
    }

    /// Clear location on a simulator
    public func clearLocation(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["location", udid, "clear"])
    }

    /// Set appearance (dark/light mode)
    public func setAppearance(udid: String, appearance: String) async throws -> SimctlResult {
        try await run(arguments: ["ui", udid, "appearance", appearance])
    }

    /// Override status bar
    public func setStatusBar(
        udid: String,
        time: String? = nil,
        batteryLevel: Int? = nil,
        batteryState: String? = nil,
        cellularBars: Int? = nil,
        wifiBars: Int? = nil
    ) async throws -> SimctlResult {
        var arguments = ["status_bar", udid, "override"]

        if let time = time {
            arguments.append(contentsOf: ["--time", time])
        }
        if let batteryLevel = batteryLevel {
            arguments.append(contentsOf: ["--batteryLevel", String(batteryLevel)])
        }
        if let batteryState = batteryState {
            arguments.append(contentsOf: ["--batteryState", batteryState])
        }
        if let cellularBars = cellularBars {
            arguments.append(contentsOf: ["--cellularBars", String(cellularBars)])
        }
        if let wifiBars = wifiBars {
            arguments.append(contentsOf: ["--wifiBars", String(wifiBars)])
        }

        return try await run(arguments: arguments)
    }

    /// Clear status bar overrides
    public func clearStatusBar(udid: String) async throws -> SimctlResult {
        try await run(arguments: ["status_bar", udid, "clear"])
    }

    /// Override status bar with options dictionary
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

/// Errors that can occur during simctl operations
public enum SimctlError: LocalizedError, Sendable {
    case commandFailed(String)
    case invalidOutput
    case deviceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return "simctl command failed: \(message)"
        case .invalidOutput:
            return "simctl returned invalid output"
        case .deviceNotFound(let udid):
            return "Simulator device not found: \(udid)"
        }
    }
}
