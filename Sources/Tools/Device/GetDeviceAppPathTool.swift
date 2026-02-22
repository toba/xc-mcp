import Foundation
import MCP
import XCMCPCore

public struct GetDeviceAppPathTool: Sendable {
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
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    guard case .string(let bundleId) = arguments["bundle_id"] else {
      throw MCPError.invalidParams("bundle_id is required")
    }

    // Get device
    let device: String
    if case .string(let value) = arguments["device"] {
      device = value
    } else if let sessionDevice = await sessionManager.deviceUDID {
      device = sessionDevice
    } else {
      throw MCPError.invalidParams(
        "device is required. Set it with set_session_defaults or pass it directly.",
      )
    }

    do {
      let result = try await deviceCtlRunner.getAppInfo(udid: device, bundleId: bundleId)

      if result.succeeded {
        return CallTool.Result(
          content: [
            .text(
              "App info for '\(bundleId)' on device '\(device)':\n\n\(result.stdout)",
            )
          ],
        )
      } else {
        throw MCPError.internalError(
          "Failed to get app info: \(result.errorOutput)",
        )
      }
    } catch {
      throw error.asMCPError()
    }
  }
}
