import Foundation
import MCP

public struct BootSimTool: Sendable {
    private let simctlRunner: SimctlRunner

    public init(simctlRunner: SimctlRunner = SimctlRunner()) {
        self.simctlRunner = simctlRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "boot_sim",
            description: "Boot a simulator by its UDID or name.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The simulator UDID or name to boot. Use list_sims to find available simulators."
                        ),
                    ])
                ]),
                "required": .array([.string("simulator")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(simulator) = arguments["simulator"] else {
            throw MCPError.invalidParams("simulator is required")
        }

        do {
            // Try to resolve simulator name to UDID if needed
            let udid = try await resolveSimulator(simulator)

            let result = try await simctlRunner.boot(udid: udid)

            if result.succeeded {
                return CallTool.Result(
                    content: [.text("Successfully booted simulator: \(simulator)")]
                )
            } else if result.stderr.contains("Unable to boot device in current state: Booted") {
                return CallTool.Result(
                    content: [.text("Simulator is already booted: \(simulator)")]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to boot simulator: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to boot simulator: \(error.localizedDescription)")
        }
    }

    private func resolveSimulator(_ identifier: String) async throws -> String {
        // If it looks like a UDID (UUID format), use it directly
        if identifier.contains("-") && identifier.count == 36 {
            return identifier
        }

        // Otherwise, search by name
        let devices = try await simctlRunner.listDevices()
        if let device = devices.first(where: { $0.name == identifier && $0.isAvailable }) {
            return device.udid
        }

        // Try partial match
        if let device = devices.first(where: {
            $0.name.lowercased().contains(identifier.lowercased()) && $0.isAvailable
        }) {
            return device.udid
        }

        throw MCPError.invalidParams(
            "Simulator not found: \(identifier). Use list_sims to see available simulators.")
    }
}
