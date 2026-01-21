import Foundation
import XCMCPCore
import MCP

public struct LongPressTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "long_press",
            description:
                "Simulate a long press at a specific coordinate on a simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "x": .object([
                        "type": .string("number"),
                        "description": .string(
                            "X coordinate of the long press location."),
                    ]),
                    "y": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Y coordinate of the long press location."),
                    ]),
                    "duration": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Duration of the long press in seconds. Defaults to 1.0."),
                    ]),
                ]),
                "required": .array([.string("x"), .string("y")]),
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

        let duration: Double
        if case let .double(value) = arguments["duration"] {
            duration = value
        } else if case let .int(value) = arguments["duration"] {
            duration = Double(value)
        } else {
            duration = 1.0
        }

        do {
            // Use simctl io to send touch event with duration (simulate long press via touch down/up)
            let result = try await simctlRunner.run(
                arguments: [
                    "io", simulator, "touch",
                    "\(x)", "\(y)",
                    "--duration", "\(duration)",
                ])

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Long pressed at (\(Int(x)), \(Int(y))) for \(duration)s on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to long press: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to long press: \(error.localizedDescription)")
        }
    }
}
