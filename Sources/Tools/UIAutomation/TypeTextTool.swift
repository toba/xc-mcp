import Foundation
import XCMCPCore
import MCP

public struct TypeTextTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "type_text",
            description:
                "Type text into the currently focused field on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Text to type."),
                    ]),
                ]),
                "required": .array([.string("text")]),
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

        // Get text
        guard case let .string(text) = arguments["text"] else {
            throw MCPError.invalidParams("text is required")
        }

        do {
            // Use simctl io to send keyboard input
            let result = try await simctlRunner.run(
                arguments: ["io", simulator, "keyboard", "text", text])

            if result.succeeded {
                let truncatedText = text.count > 20 ? String(text.prefix(20)) + "..." : text
                return CallTool.Result(
                    content: [
                        .text(
                            "Typed '\(truncatedText)' on simulator '\(simulator)'"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to type text: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to type text: \(error.localizedDescription)")
        }
    }
}
