import MCP
import XCMCPCore
import Foundation

public struct StopAppDeviceTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager,
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "stop_app_device",
            description:
            "Stop (terminate) a running app on a connected device by its bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to stop (e.g., 'com.example.MyApp').",
                        ),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID. Uses session default if not specified.",
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_id")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleId = try arguments.getRequiredString("bundle_id")
        let device = try await sessionManager.resolveDevice(from: arguments)

        do {
            let result = try await deviceCtlRunner.terminate(udid: device, bundleId: bundleId)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text("Successfully stopped '\(bundleId)' on device '\(device)'"),
                    ],
                )
            } else {
                throw MCPError.internalError(
                    "Failed to stop app: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
