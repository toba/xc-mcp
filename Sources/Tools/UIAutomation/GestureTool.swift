import MCP
import XCMCPCore
import Foundation

public struct GestureTool: Sendable {
    private let uiInput: SimulatorUIInput
    private let sessionManager: SessionManager

    public init(uiInput: SimulatorUIInput = .init(), sessionManager: SessionManager) {
        self.uiInput = uiInput
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "gesture",
            description:
                "Perform a named gesture preset on a simulator screen. Presets compute coordinates relative to screen dimensions so you don't need to calculate them manually.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "preset": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Gesture preset name: scroll_up, scroll_down, scroll_left, scroll_right, swipe_from_left_edge, swipe_from_right_edge, pull_to_refresh, swipe_down_to_dismiss",
                        ),
                        "enum": .array([
                            .string("scroll_up"),
                            .string("scroll_down"),
                            .string("scroll_left"),
                            .string("scroll_right"),
                            .string("swipe_from_left_edge"),
                            .string("swipe_from_right_edge"),
                            .string("pull_to_refresh"),
                            .string("swipe_down_to_dismiss"),
                        ]),
                    ]),
                ]),
                "required": .array([.string("preset")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        let presetName = try arguments.getRequiredString("preset")

        guard let preset = GesturePreset(rawValue: presetName) else {
            throw MCPError.invalidParams(
                "Unknown gesture preset '\(presetName)'. Valid presets: \(GesturePreset.allCases.map(\.rawValue).joined(separator: ", "))",
            )
        }

        // Presets are screen-relative; evaluating against a 1×1 box yields fractional coordinates
        // that the host-side mapper resolves to the actual on-screen device rectangle.
        let coords = preset.coordinates(width: 1, height: 1)

        do {
            try await uiInput.swipeFraction(
                simulator: simulator,
                startX: coords.startX, startY: coords.startY,
                endX: coords.endX, endY: coords.endY,
                duration: coords.duration,
            )
            return CallTool.Result(content: [
                .text(
                    text: "Performed '\(presetName)' gesture on simulator '\(simulator)'",
                    annotations: nil, _meta: nil)
            ],)
        } catch {
            throw try error.asMCPError()
        }
    }
}

// MARK: - Gesture Presets

private enum GesturePreset: String, CaseIterable {
    case scrollUp = "scroll_up"
    case scrollDown = "scroll_down"
    case scrollLeft = "scroll_left"
    case scrollRight = "scroll_right"
    case swipeFromLeftEdge = "swipe_from_left_edge"
    case swipeFromRightEdge = "swipe_from_right_edge"
    case pullToRefresh = "pull_to_refresh"
    case swipeDownToDismiss = "swipe_down_to_dismiss"

    struct SwipeCoordinates {
        let startX: Double
        let startY: Double
        let endX: Double
        let endY: Double
        let duration: Double
    }

    func coordinates(width w: Double, height h: Double) -> SwipeCoordinates {
        switch self {
            case .scrollUp:
                SwipeCoordinates(
                    startX: 0.5 * w, startY: 0.7 * h, endX: 0.5 * w, endY: 0.3 * h, duration: 0.5,
                )
            case .scrollDown:
                SwipeCoordinates(
                    startX: 0.5 * w, startY: 0.3 * h, endX: 0.5 * w, endY: 0.7 * h, duration: 0.5,
                )
            case .scrollLeft:
                SwipeCoordinates(
                    startX: 0.8 * w, startY: 0.5 * h, endX: 0.2 * w, endY: 0.5 * h, duration: 0.5,
                )
            case .scrollRight:
                SwipeCoordinates(
                    startX: 0.2 * w, startY: 0.5 * h, endX: 0.8 * w, endY: 0.5 * h, duration: 0.5,
                )
            case .swipeFromLeftEdge:
                SwipeCoordinates(
                    startX: 0, startY: 0.5 * h, endX: 0.4 * w, endY: 0.5 * h, duration: 0.3,
                )
            case .swipeFromRightEdge:
                SwipeCoordinates(
                    startX: w, startY: 0.5 * h, endX: 0.6 * w, endY: 0.5 * h, duration: 0.3,
                )
            case .pullToRefresh:
                SwipeCoordinates(
                    startX: 0.5 * w, startY: 0.15 * h, endX: 0.5 * w, endY: 0.6 * h, duration: 0.5,
                )
            case .swipeDownToDismiss:
                SwipeCoordinates(
                    startX: 0.5 * w, startY: 0.1 * h, endX: 0.5 * w, endY: 0.9 * h, duration: 0.5,
                )
        }
    }
}
