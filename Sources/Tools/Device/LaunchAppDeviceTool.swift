import MCP
import XCMCPCore
import Foundation

public struct LaunchAppDeviceTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "launch_app_device",
            description: "Launch an app on a connected device by its bundle identifier.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app to launch (e.g., 'com.example.MyApp').",
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
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleID = try arguments.getRequiredString("bundle_id")
        let device = try await sessionManager.resolveDevice(from: arguments)

        do {
            let result = try await deviceCtlRunner.launch(udid: device, bundleID: bundleID)

            if result.succeeded {
                return CallTool.Result.text(
                    "Successfully launched '\(bundleID)' on device '\(device)'")
            } else {
                throw MCPError.internalError("Failed to launch app: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
