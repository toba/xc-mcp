import Foundation
import MCP

public struct InstallAppDeviceTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "install_app_device",
            description: "Install an app (.app bundle or .ipa) on a connected device.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .app bundle or .ipa file to install."),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID. Uses session default if not specified."),
                    ]),
                ]),
                "required": .array([.string("app_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(appPath) = arguments["app_path"] else {
            throw MCPError.invalidParams("app_path is required")
        }

        // Get device
        let device: String
        if case let .string(value) = arguments["device"] {
            device = value
        } else if let sessionDevice = await sessionManager.deviceUDID {
            device = sessionDevice
        } else {
            throw MCPError.invalidParams(
                "device is required. Set it with set_session_defaults or pass it directly.")
        }

        do {
            let result = try await deviceCtlRunner.install(udid: device, appPath: appPath)

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text("Successfully installed app at '\(appPath)' on device '\(device)'")
                    ]
                )
            } else {
                throw MCPError.internalError(
                    "Failed to install app: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to install app: \(error.localizedDescription)")
        }
    }
}
