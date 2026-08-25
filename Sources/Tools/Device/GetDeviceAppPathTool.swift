import MCP
import XCMCPCore
import Foundation

public struct GetDeviceAppPathTool: Sendable {
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
            name: "get_device_app_path",
            description:
                "Get information about an installed app on a connected device, including its installation path.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The bundle identifier of the app (e.g., 'com.example.MyApp').",
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
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleID = try arguments.getRequiredString("bundle_id")

        let device = try await sessionManager.resolveDevice(from: arguments)

        do {
            let result = try await deviceCtlRunner.getAppInfo(udid: device, bundleID: bundleID)

            if result.succeeded {
                return CallTool.Result.text(
                    "App info for '\(bundleID)' on device '\(device)':\n\n\(result.stdout)")
            } else {
                throw MCPError.internalError("Failed to get app info: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
