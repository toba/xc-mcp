import MCP
import XCMCPCore
import Foundation

public struct TapTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "tap",
            description:
            "Simulate a tap at a specific coordinate on a simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "x": .object([
                        "type": .string("number"),
                        "description": .string(
                            "X coordinate of the tap location.",
                        ),
                    ]),
                    "y": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Y coordinate of the tap location.",
                        ),
                    ]),
                ]),
                "required": .array([.string("x"), .string("y")]),
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
        let x: Double
        if case let .double(value) = arguments["x"] {
            x = value
        } else if case let .int(value) = arguments["x"] {
            x = Double(value)
        } else {
            throw MCPError.invalidParams("x coordinate is required")
        }

        let y: Double
        if case let .double(value) = arguments["y"] {
            y = value
        } else if case let .int(value) = arguments["y"] {
            y = Double(value)
        } else {
            throw MCPError.invalidParams("y coordinate is required")
        }

        do {
            // Use simctl io to send touch event
            let result = try await simctlRunner.run(
                arguments: ["io", simulator, "tap", "\(x)", "\(y)"],
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Tapped at (\(Int(x)), \(Int(y))) on simulator '\(simulator)'",
                        ),
                        NextStepHints.content(hints: [
                            NextStepHint(
                                tool: "screenshot",
                                description: "Take a screenshot to verify the result",
                            ),
                            NextStepHint(tool: "tap", description: "Tap another UI element"),
                            NextStepHint(
                                tool: "type_text", description: "Type text into a focused field",
                            ),
                        ]),
                    ],
                )
            } else {
                throw MCPError.internalError(
                    "Failed to tap: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
