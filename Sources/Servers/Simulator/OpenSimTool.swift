import Foundation
import MCP
import XCMCPCore

public struct OpenSimTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "open_sim",
            description:
                "Open the Simulator.app. Optionally specify a simulator UDID to open a specific device.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional simulator UDID to open. If not specified, opens Simulator.app with the default device."
                        ),
                    ])
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let simulator: String?
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else {
            simulator = nil
        }

        do {
            if let udid = simulator {
                // Open specific simulator
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = [
                    "-a", "Simulator",
                    "--args", "-CurrentDeviceUDID", udid,
                ]

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    return CallTool.Result(
                        content: [.text("Opened Simulator.app with device: \(udid)")]
                    )
                } else {
                    throw MCPError.internalError("Failed to open Simulator.app")
                }
            } else {
                // Just open Simulator.app
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", "Simulator"]

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    return CallTool.Result(
                        content: [.text("Opened Simulator.app")]
                    )
                } else {
                    throw MCPError.internalError("Failed to open Simulator.app")
                }
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to open Simulator.app: \(error.localizedDescription)")
        }
    }
}
