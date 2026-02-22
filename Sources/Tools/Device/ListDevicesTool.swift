import MCP
import XCMCPCore
import Foundation

/// MCP tool for listing connected physical iOS/tvOS/watchOS devices.
///
/// Uses devicectl to enumerate all connected devices with their UDIDs,
/// names, device types, OS versions, and connection types.
public struct ListDevicesTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner

    /// Creates a new ListDevicesTool instance.
    ///
    /// - Parameter deviceCtlRunner: Runner for executing devicectl commands.
    public init(deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner()) {
        self.deviceCtlRunner = deviceCtlRunner
    }

    /// Returns the MCP tool definition.
    public func tool() -> Tool {
        Tool(
            name: "list_devices",
            description:
            "List all connected iOS/tvOS/watchOS devices with their UDIDs and details.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([]),
            ]),
        )
    }

    /// Executes the tool to list connected devices.
    ///
    /// - Parameter arguments: Dictionary of arguments (none required).
    /// - Returns: The result containing list of devices or message if none found.
    /// - Throws: MCPError if device listing fails.
    public func execute(arguments _: [String: Value]) async throws -> CallTool.Result {
        do {
            let devices = try await deviceCtlRunner.listDevices()

            if devices.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(
                            "No connected devices found. Make sure your device is connected and trusted.",
                        ),
                    ],
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
