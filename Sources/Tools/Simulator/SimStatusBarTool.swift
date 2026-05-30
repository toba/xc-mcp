import MCP
import XCMCPCore
import Foundation

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
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "time": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Time to display (e.g., '9:41' for classic Apple time).",
                        ),
                    ]),
                    "battery_level": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Battery level percentage (0-100).",
                        ),
                    ]),
                    "battery_state": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Battery state: 'charging', 'charged', or 'discharging'.",
                        ),
                    ]),
                    "cellular_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Cellular mode: 'notSupported', 'searching', 'failed', 'active'.",
                        ),
                    ]),
                    "cellular_bars": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Cellular signal bars (0-4).",
                        ),
                    ]),
                    "wifi_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "WiFi mode: 'searching', 'failed', 'active'.",
                        ),
                    ]),
                    "wifi_bars": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "WiFi signal bars (0-3).",
                        ),
                    ]),
                    "clear": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Clear all status bar overrides and return to normal.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
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
                "simulator is required. Set it with set_session_defaults or pass it directly.",
            )
        }

        // Check if we should clear
        if arguments.getBool("clear") {
            do {
                let result = try await simctlRunner.clearStatusBar(udid: simulator)

                if result.succeeded {
                    return CallTool.Result(
                        content: [
                            .text(text:
                                "Successfully cleared status bar overrides on simulator '\(simulator)'",
                                annotations: nil, _meta: nil),
                        ],
                    )
                } else {
                    throw MCPError.internalError(
                        "Failed to clear status bar: \(result.errorOutput)",
                    )
                }
            } catch {
                throw try error.asMCPError()
            }
        }

        let time = arguments.getString("time")
        let batteryLevel = arguments.getInt("battery_level")
        let batteryState = arguments.getString("battery_state")
        let cellularMode = arguments.getString("cellular_mode")
        let cellularBars = arguments.getInt("cellular_bars")
        let wifiMode = arguments.getString("wifi_mode")
        let wifiBars = arguments.getInt("wifi_bars")

        var setOptions: [String] = []
        if time != nil { setOptions.append("time") }
        if batteryLevel != nil { setOptions.append("batteryLevel") }
        if batteryState != nil { setOptions.append("batteryState") }
        if cellularMode != nil { setOptions.append("cellularMode") }
        if cellularBars != nil { setOptions.append("cellularBars") }
        if wifiMode != nil { setOptions.append("wifiMode") }
        if wifiBars != nil { setOptions.append("wifiBars") }

        if setOptions.isEmpty {
            throw MCPError.invalidParams(
                "At least one status bar option is required, or use 'clear: true' to reset.",
            )
        }

        do {
            let result = try await simctlRunner.setStatusBar(
                udid: simulator,
                time: time,
                batteryLevel: batteryLevel,
                batteryState: batteryState,
                cellularMode: cellularMode,
                cellularBars: cellularBars,
                wifiMode: wifiMode,
                wifiBars: wifiBars,
            )

            if result.succeeded {
                let optionsList = setOptions.sorted().joined(separator: ", ")
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Successfully set status bar overrides (\(optionsList)) on simulator '\(simulator)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            } else {
                throw MCPError.internalError(
                    "Failed to set status bar: \(result.errorOutput)",
                )
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
