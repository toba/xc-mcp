import Foundation
import XCMCPCore
import MCP

public struct ScreenshotTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "screenshot",
            description:
                "Take a screenshot of a simulator screen.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to save the screenshot. Defaults to /tmp/screenshot_<timestamp>.png"
                        ),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Image format: 'png' or 'jpeg'. Defaults to 'png'."),
                    ]),
                ]),
                "required": .array([]),
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

        // Get output path
        let outputPath: String
        if case let .string(value) = arguments["output_path"] {
            outputPath = value
        } else {
            let timestamp = Int(Date().timeIntervalSince1970)
            outputPath = "/tmp/screenshot_\(timestamp).png"
        }

        // Get format
        let format: String
        if case let .string(value) = arguments["format"] {
            format = value.lowercased()
        } else {
            format = "png"
        }

        // Adjust output path extension if needed
        var finalPath = outputPath
        if !finalPath.hasSuffix(".\(format)") {
            if finalPath.hasSuffix(".png") || finalPath.hasSuffix(".jpeg")
                || finalPath.hasSuffix(".jpg")
            {
                let pathWithoutExt =
                    URL(fileURLWithPath: finalPath).deletingPathExtension().path
                finalPath = "\(pathWithoutExt).\(format)"
            } else {
                finalPath = "\(finalPath).\(format)"
            }
        }

        do {
            let result = try await simctlRunner.screenshot(udid: simulator, outputPath: finalPath)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Screenshot saved to: \(finalPath)"
                        )
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to take screenshot: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to take screenshot: \(error.localizedDescription)")
        }
    }
}
