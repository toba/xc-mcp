import MCP
import XCMCPCore
import Foundation

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
                            "Optional simulator UDID to open. If not specified, opens Simulator.app with the default device.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = arguments.getString("simulator")

        do {
            guard let args = FocusPolicy.openSimulatorAppArgs(simulatorId: simulator) else {
                let message = "Simulator.app launch skipped by \(FocusPolicy.envVar)"
                return CallTool.Result(content: [.text(
                    text: message,
                    annotations: nil,
                    _meta: nil,
                )])
            }

            let result = try await ProcessResult.run("/usr/bin/open", arguments: args)

            if result.succeeded {
                let message =
                    simulator != nil
                        ? "Opened Simulator.app with device: \(simulator!)"
                        : "Opened Simulator.app"
                return CallTool.Result(content: [.text(
                    text: message,
                    annotations: nil,
                    _meta: nil,
                )])
            } else {
                throw MCPError.internalError("Failed to open Simulator.app")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
