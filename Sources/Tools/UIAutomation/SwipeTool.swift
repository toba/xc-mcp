import MCP
import XCMCPCore
import Foundation

public struct SwipeTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swipe",
            description:
            "Simulate a swipe gesture on a simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "start_x": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Starting X coordinate.",
                        ),
                    ]),
                    "start_y": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Starting Y coordinate.",
                        ),
                    ]),
                    "end_x": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Ending X coordinate.",
                        ),
                    ]),
                    "end_y": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Ending Y coordinate.",
                        ),
                    ]),
                    "duration": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Duration of the swipe in seconds. Defaults to 0.5.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("start_x"), .string("start_y"), .string("end_x"), .string("end_y"),
                ]),
            ]),
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

        // Get coordinates
        let startX: Double
        if case let .double(value) = arguments["start_x"] {
            startX = value
        } else if case let .int(value) = arguments["start_x"] {
            startX = Double(value)
        } else {
            throw MCPError.invalidParams("start_x coordinate is required")
        }

        let startY: Double
        if case let .double(value) = arguments["start_y"] {
            startY = value
        } else if case let .int(value) = arguments["start_y"] {
            startY = Double(value)
        } else {
            throw MCPError.invalidParams("start_y coordinate is required")
        }

        let endX: Double
        if case let .double(value) = arguments["end_x"] {
            endX = value
        } else if case let .int(value) = arguments["end_x"] {
            endX = Double(value)
        } else {
            throw MCPError.invalidParams("end_x coordinate is required")
        }

        let endY: Double
        if case let .double(value) = arguments["end_y"] {
            endY = value
        } else if case let .int(value) = arguments["end_y"] {
            endY = Double(value)
        } else {
            throw MCPError.invalidParams("end_y coordinate is required")
        }

        let duration: Double
        if case let .double(value) = arguments["duration"] {
            duration = value
        } else if case let .int(value) = arguments["duration"] {
            duration = Double(value)
        } else {
            duration = 0.5
        }

        do {
            // Use simctl io to send swipe event
            let result = try await simctlRunner.run(
                arguments: [
                    "io", simulator, "swipe",
                    "\(startX)", "\(startY)", "\(endX)", "\(endY)",
                    "--duration", "\(duration)",
                ],
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Swiped from (\(Int(startX)), \(Int(startY))) to (\(Int(endX)), \(Int(endY))) on simulator '\(simulator)'",
                        ),
                    ],
                )
            } else {
                throw MCPError.internalError(
                    "Failed to swipe: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
