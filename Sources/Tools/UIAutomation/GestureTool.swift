import Foundation
import MCP
import XCMCPCore

public struct GestureTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "gesture",
            description:
                "Perform a named gesture preset on a simulator screen. Presets compute coordinates relative to screen dimensions so you don't need to calculate them manually.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."
                        ),
                    ]),
                    "preset": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Gesture preset name: scroll_up, scroll_down, scroll_left, scroll_right, swipe_from_left_edge, swipe_from_right_edge, pull_to_refresh, swipe_down_to_dismiss"
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
                    "screen_width": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Screen width in points. Defaults to 393 (iPhone 15 Pro)."
                        ),
                    ]),
                    "screen_height": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Screen height in points. Defaults to 852 (iPhone 15 Pro)."
                        ),
                    ]),
                ]),
                "required": .array([.string("preset")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        let presetName = try arguments.getRequiredString("preset")

        let screenWidth: Double
        if let w = arguments.getDouble("screen_width") {
            screenWidth = w
        } else if let w = arguments.getInt("screen_width") {
            screenWidth = Double(w)
        } else {
            screenWidth = 393
        }

        let screenHeight: Double
        if let h = arguments.getDouble("screen_height") {
            screenHeight = h
        } else if let h = arguments.getInt("screen_height") {
            screenHeight = Double(h)
        } else {
            screenHeight = 852
        }

        guard let preset = GesturePreset(rawValue: presetName) else {
            throw MCPError.invalidParams(
                "Unknown gesture preset '\(presetName)'. Valid presets: \(GesturePreset.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let coords = preset.coordinates(width: screenWidth, height: screenHeight)

        do {
            let result = try await simctlRunner.run(
                arguments: [
                    "io", simulator, "swipe",
                    "\(coords.startX)", "\(coords.startY)",
                    "\(coords.endX)", "\(coords.endY)",
                    "--duration", "\(coords.duration)",
                ]
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Performed '\(presetName)' gesture on simulator '\(simulator)' — swiped from (\(Int(coords.startX)), \(Int(coords.startY))) to (\(Int(coords.endX)), \(Int(coords.endY)))"
                        ),
                        NextStepHints.content(hints: [
                            NextStepHint(
                                tool: "screenshot",
                                description: "Take a screenshot to verify the result"
                            ),
                            NextStepHint(
                                tool: "gesture", description: "Perform another gesture preset"
                            ),
                        ]),
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to perform gesture: \(result.errorOutput)"
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}

// MARK: - Gesture Presets

private enum GesturePreset: String, CaseIterable, Sendable {
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
            return SwipeCoordinates(
                startX: 0.5 * w, startY: 0.7 * h, endX: 0.5 * w, endY: 0.3 * h, duration: 0.5
            )
        case .scrollDown:
            return SwipeCoordinates(
                startX: 0.5 * w, startY: 0.3 * h, endX: 0.5 * w, endY: 0.7 * h, duration: 0.5
            )
        case .scrollLeft:
            return SwipeCoordinates(
                startX: 0.8 * w, startY: 0.5 * h, endX: 0.2 * w, endY: 0.5 * h, duration: 0.5
            )
        case .scrollRight:
            return SwipeCoordinates(
                startX: 0.2 * w, startY: 0.5 * h, endX: 0.8 * w, endY: 0.5 * h, duration: 0.5
            )
        case .swipeFromLeftEdge:
            return SwipeCoordinates(
                startX: 0, startY: 0.5 * h, endX: 0.4 * w, endY: 0.5 * h, duration: 0.3
            )
        case .swipeFromRightEdge:
            return SwipeCoordinates(
                startX: w, startY: 0.5 * h, endX: 0.6 * w, endY: 0.5 * h, duration: 0.3
            )
        case .pullToRefresh:
            return SwipeCoordinates(
                startX: 0.5 * w, startY: 0.15 * h, endX: 0.5 * w, endY: 0.6 * h, duration: 0.5
            )
        case .swipeDownToDismiss:
            return SwipeCoordinates(
                startX: 0.5 * w, startY: 0.1 * h, endX: 0.5 * w, endY: 0.9 * h, duration: 0.5
            )
        }
    }
}
