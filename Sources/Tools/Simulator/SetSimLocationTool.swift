import MCP
import XCMCPCore
import Foundation

public struct SetSimLocationTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "set_sim_location",
            description:
                "Set the simulated location on a simulator. Useful for testing location-based features.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "latitude": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Latitude coordinate (e.g., 37.7749 for San Francisco).",
                        ),
                    ]),
                    "longitude": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Longitude coordinate (e.g., -122.4194 for San Francisco).",
                        ),
                    ]),
                ]),
                "required": .array([.string("latitude"), .string("longitude")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

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
                longitude: longitude,
            )

            if result.succeeded {
                return CallTool.Result.text(
                    "Successfully set location to (\(latitude), \(longitude)) on simulator '\(simulator)'"
                )
            } else {
                throw MCPError.internalError("Failed to set location: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
