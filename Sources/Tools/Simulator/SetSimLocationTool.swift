import Foundation
import MCP
import XCMCPCore

public struct SetSimLocationTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "set_sim_location",
            description:
                "Set the simulated location on a simulator. Useful for testing location-based features.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."
                        ),
                    ]),
                    "latitude": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Latitude coordinate (e.g., 37.7749 for San Francisco)."
                        ),
                    ]),
                    "longitude": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Longitude coordinate (e.g., -122.4194 for San Francisco)."
                        ),
                    ]),
                ]),
                "required": .array([.string("latitude"), .string("longitude")]),
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
                "simulator is required. Set it with set_session_defaults or pass it directly."
            )
        }

        // Get latitude
        let latitude: Double
        if case let .double(value) = arguments["latitude"] {
            latitude = value
        } else if case let .int(value) = arguments["latitude"] {
            latitude = Double(value)
        } else {
            throw MCPError.invalidParams("latitude is required")
        }

        // Get longitude
        let longitude: Double
        if case let .double(value) = arguments["longitude"] {
            longitude = value
        } else if case let .int(value) = arguments["longitude"] {
            longitude = Double(value)
        } else {
            throw MCPError.invalidParams("longitude is required")
        }

        do {
            let result = try await simctlRunner.setLocation(
                udid: simulator,
                latitude: latitude,
                longitude: longitude
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully set location to (\(latitude), \(longitude)) on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to set location: \(result.errorOutput)"
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
