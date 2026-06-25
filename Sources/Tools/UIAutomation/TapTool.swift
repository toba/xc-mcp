import MCP
import XCMCPCore
import Foundation

public struct TapTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "tap",
            description:
                "Simulate a tap at a specific coordinate on a booted simulator screen. Coordinates are "
                + "in device pixels — the same space as the `screenshot` tool's image (e.g. "
                + "1206×2622 on iPhone 17), so you can read a point straight off a screenshot. Drives "
                + "the on-screen Simulator window, so the Simulator app must be visible.",
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
                        "description": .string("X coordinate of the tap location."),
                    ]),
                    "y": .object([
                        "type": .string("number"),
                        "description": .string("Y coordinate of the tap location."),
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

        do {
            try await uiInput.tap(simulator: simulator, x: x, y: y)
            return CallTool.Result(content: [
                .text(
                    text: "Tapped at (\(Int(x)), \(Int(y))) on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}
