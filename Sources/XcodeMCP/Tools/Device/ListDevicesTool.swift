import Foundation
import MCP

public struct ListDevicesTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner

    public init(deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner()) {
        self.deviceCtlRunner = deviceCtlRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "list_devices",
            description:
                "List all connected iOS/tvOS/watchOS devices with their UDIDs and details.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let devices = try await deviceCtlRunner.listDevices()

            if devices.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(
                            "No connected devices found. Make sure your device is connected and trusted."
                        )
                    ]
                )
            }

            var output = "Found \(devices.count) connected device(s):\n\n"

            for device in devices {
                output += "📱 \(device.name)\n"
                output += "   UDID: \(device.udid)\n"
                output += "   Type: \(device.deviceType)\n"
                output += "   OS Version: \(device.osVersion)\n"
                output += "   Connection: \(device.connectionType)\n\n"
            }

            return CallTool.Result(content: [.text(output)])
        } catch {
            throw MCPError.internalError("Failed to list devices: \(error.localizedDescription)")
        }
    }
}
