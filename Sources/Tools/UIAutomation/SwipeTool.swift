import MCP
import XCMCPCore
import Foundation

public struct SwipeTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "swipe",
            description:
                "Simulate a swipe gesture on a booted simulator screen. Start/end coordinates are in "
                + "device pixels (as in the `screenshot` image). Drives the on-screen Simulator "
                + "window.",
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
                        "type": .string("number"), "description": .string("Starting X coordinate."),
                    ]),
                    "start_y": .object([
                        "type": .string("number"), "description": .string("Starting Y coordinate."),
                    ]),
                    "end_x": .object([
                        "type": .string("number"), "description": .string("Ending X coordinate."),
                    ]),
                    "end_y": .object([
                        "type": .string("number"), "description": .string("Ending Y coordinate."),
                    ]),
                    "duration": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Duration of the swipe in seconds. Defaults to 0.5."),
                    ]),
                ]),
                "required": .array([
                    .string("start_x"), .string("start_y"), .string("end_x"), .string("end_y"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        func coord(_ key: String) throws -> Double {
            guard let value = arguments.getDouble(key) ?? arguments.getInt(key).map(Double.init)
            else { throw MCPError.invalidParams("\(key) coordinate is required") }
            return value
        }
        let startX = try coord("start_x")
        let startY = try coord("start_y")
        let endX = try coord("end_x")
        let endY = try coord("end_y")
        let duration = arguments.getDouble("duration")
            ?? arguments.getInt("duration").map(Double.init) ?? 0.5

        do {
            try await uiInput.swipe(
                simulator: simulator,
                startX: startX, startY: startY, endX: endX, endY: endY, duration: duration,
            )
            return CallTool.Result(content: [
                .text(
                    text: "Swiped from (\(Int(startX)), \(Int(startY))) to (\(Int(endX)), \(Int(endY))) on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}
