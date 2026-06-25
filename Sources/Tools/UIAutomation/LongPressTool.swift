import MCP
import XCMCPCore
import Foundation

public struct LongPressTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "long_press",
            description:
                "Simulate a long press at a specific coordinate (device pixels, as in the `screenshot` "
                + "image) on a booted simulator screen. Drives the on-screen Simulator window.",
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
                        "description": .string("X coordinate of the long press location."),
                    ]),
                    "y": .object([
                        "type": .string("number"),
                        "description": .string("Y coordinate of the long press location."),
                    ]),
                    "duration": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Duration of the long press in seconds. Defaults to 1.0.",
                        ),
                    ]),
                ]),
                "required": .array([.string("x"), .string("y")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        guard let x = arguments.getDouble("x") ?? arguments.getInt("x").map(Double.init) else {
            throw MCPError.invalidParams("x coordinate is required")
        }
        guard let y = arguments.getDouble("y") ?? arguments.getInt("y").map(Double.init) else {
            throw MCPError.invalidParams("y coordinate is required")
        }
        let duration = arguments.getDouble("duration")
            ?? arguments.getInt("duration").map(Double.init) ?? 1.0

        do {
            try await uiInput.longPress(simulator: simulator, x: x, y: y, duration: duration)
            return CallTool.Result(content: [
                .text(
                    text: "Long pressed at (\(Int(x)), \(Int(y))) for \(duration)s on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}
