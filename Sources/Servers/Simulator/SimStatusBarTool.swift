import Foundation
import MCP
import XCMCPCore

public struct SimStatusBarTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "sim_statusbar",
            description:
                "Override the status bar display on a simulator. Useful for taking clean screenshots.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "time": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Time to display (e.g., '9:41' for classic Apple time)."),
                    ]),
                    "battery_level": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Battery level percentage (0-100)."),
                    ]),
                    "battery_state": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Battery state: 'charging', 'charged', or 'discharging'."),
                    ]),
                    "cellular_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Cellular mode: 'notSupported', 'searching', 'failed', 'active'."),
                    ]),
                    "cellular_bars": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Cellular signal bars (0-4)."),
                    ]),
                    "wifi_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "WiFi mode: 'searching', 'failed', 'active'."),
                    ]),
                    "wifi_bars": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "WiFi signal bars (0-3)."),
                    ]),
                    "clear": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Clear all status bar overrides and return to normal."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly.")
        }

        // Check if we should clear
        if case let .bool(clear) = arguments["clear"], clear {
            do {
                let result = try await simctlRunner.clearStatusBar(udid: simulator)

                if result.succeeded {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Successfully cleared status bar overrides on simulator '\(simulator)'"
                            )
                        ]
                    )
                } else {
                    throw MCPError.internalError(
                        "Failed to clear status bar: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                    )
                }
            } catch let error as MCPError {
                throw error
            } catch {
                throw MCPError.internalError(
                    "Failed to clear status bar: \(error.localizedDescription)")
            }
        }

        // Build status bar override options
        var options: [String: Any] = [:]

        if case let .string(time) = arguments["time"] {
            options["time"] = time
        }
        if case let .int(batteryLevel) = arguments["battery_level"] {
            options["batteryLevel"] = batteryLevel
        }
        if case let .string(batteryState) = arguments["battery_state"] {
            options["batteryState"] = batteryState
        }
        if case let .string(cellularMode) = arguments["cellular_mode"] {
            options["cellularMode"] = cellularMode
        }
        if case let .int(cellularBars) = arguments["cellular_bars"] {
            options["cellularBars"] = cellularBars
        }
        if case let .string(wifiMode) = arguments["wifi_mode"] {
            options["wifiMode"] = wifiMode
        }
        if case let .int(wifiBars) = arguments["wifi_bars"] {
            options["wifiBars"] = wifiBars
        }

        if options.isEmpty {
            throw MCPError.invalidParams(
                "At least one status bar option is required, or use 'clear: true' to reset.")
        }

        do {
            let result = try await simctlRunner.overrideStatusBar(
                udid: simulator, options: options)

            if result.succeeded {
                let optionsList = options.keys.sorted().joined(separator: ", ")
                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully set status bar overrides (\(optionsList)) on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to set status bar: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to set status bar: \(error.localizedDescription)")
        }
    }
}
