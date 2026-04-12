import CoreGraphics
import Foundation
import ImageIO
import MCP
import XCMCPCore

public struct ScreenshotMacWindowTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "screenshot_mac_window",
            description:
            "Take a screenshot of a macOS application window. "
                +
                "Returns the image inline as base64 PNG. Requires Screen Recording permission in System Settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Application name to match (e.g., 'Finder', 'Safari'). Matches against the owning application's name.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier to match (e.g., 'com.apple.finder'). Matches against the owning application's bundle identifier.",
                        ),
                    ]),
                    "window_title": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Window title to match. Matches against the window's title.",
                        ),
                    ]),
                    "save_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional file path to also save the screenshot as a PNG file.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let appName = arguments.getString("app_name")
        let bundleId = arguments.getString("bundle_id")
        let windowTitle = arguments.getString("window_title")
        let savePath = arguments.getString("save_path")

        if appName == nil, bundleId == nil, windowTitle == nil {
            throw MCPError.invalidParams(
                "At least one of app_name, bundle_id, or window_title is required.",
            )
        }

        let window = try WindowCapture.findWindow(
            appName: appName, bundleId: bundleId, windowTitle: windowTitle,
        )
        let pngData = try await WindowCapture.capture(
            windowID: window.windowID, savePath: savePath,
        )

        // Get image dimensions for the description
        let width: Int
        let height: Int
        if let imageSource = CGImageSourceCreateWithData(pngData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
        {
            width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        } else {
            width = 0
            height = 0
        }

        let base64 = pngData.base64EncodedString()
        let windowName = window.windowName ?? "untitled"
        let appInfo = window.ownerName ?? "unknown"

        var description =
            "Screenshot of '\(appInfo)' window '\(windowName)' (\(width)x\(height) px)"
        if let savePath {
            description += "\nSaved to: \(savePath)"
        }

        return CallTool.Result(
            content: [
                .image(data: base64, mimeType: "image/png", annotations: nil, _meta: nil),
                .text(text: description, annotations: nil, _meta: nil),
            ],
        )
    }
}
