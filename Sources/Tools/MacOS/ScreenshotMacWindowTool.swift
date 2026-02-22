import AppKit
import Foundation
import MCP
import ScreenCaptureKit

public struct ScreenshotMacWindowTool: Sendable {
  public init() {}

  public func tool() -> Tool {
    Tool(
      name: "screenshot_mac_window",
      description:
        "Take a screenshot of a macOS application window using ScreenCaptureKit. "
        + "Returns the image inline as base64 PNG. Requires Screen Recording permission in System Settings.",
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
    )
  }

  /// Ensures the process has a WindowServer connection for ScreenCaptureKit.
  private static func ensureGUIConnection() async {
    await MainActor.run {
      NSApplication.shared.setActivationPolicy(.accessory)
    }
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    await Self.ensureGUIConnection()

    let appName = arguments.getString("app_name")
    let bundleId = arguments.getString("bundle_id")
    let windowTitle = arguments.getString("window_title")
    let savePath = arguments.getString("save_path")

    if appName == nil, bundleId == nil, windowTitle == nil {
      throw MCPError.invalidParams(
        "At least one of app_name, bundle_id, or window_title is required.",
      )
    }

    // Get available windows
    let availableContent: SCShareableContent
    do {
      availableContent = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true,
      )
    } catch {
      throw MCPError.internalError(
        "Failed to get screen content. Ensure Screen Recording permission is granted in "
          + "System Settings > Privacy & Security > Screen Recording. Error: \(error.localizedDescription)",
      )
    }

    // Filter windows
    let matchingWindows = availableContent.windows.filter { window in
      if let appName {
        guard
          let name = window.owningApplication?.applicationName,
          name.localizedCaseInsensitiveContains(appName)
        else { return false }
      }
      if let bundleId {
        guard
          let id = window.owningApplication?.bundleIdentifier,
          id.localizedCaseInsensitiveContains(bundleId)
        else { return false }
      }
      if let windowTitle {
        guard
          let title = window.title,
          title.localizedCaseInsensitiveContains(windowTitle)
        else { return false }
      }
      return true
    }

    guard let targetWindow = matchingWindows.first else {
      var criteria: [String] = []
      if let appName { criteria.append("app_name='\(appName)'") }
      if let bundleId { criteria.append("bundle_id='\(bundleId)'") }
      if let windowTitle { criteria.append("window_title='\(windowTitle)'") }
      throw MCPError.invalidParams(
        "No window found matching \(criteria.joined(separator: ", ")). "
          + "Make sure the app is running and has a visible window.",
      )
    }

    // Capture the window
    let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
    let config = SCStreamConfiguration()
    config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
    config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))

    let cgImage: CGImage
    do {
      cgImage = try await withCheckedThrowingContinuation { continuation in
        SCScreenshotManager.captureImage(
          contentFilter: filter, configuration: config,
        ) { image, error in
          if let error {
            continuation.resume(throwing: error)
          } else if let image {
            continuation.resume(returning: image)
          } else {
            continuation.resume(
              throwing: MCPError.internalError(
                "Screenshot capture returned nil image.",
              ),
            )
          }
        }
      }
    } catch {
      throw MCPError.internalError(
        "Failed to capture window screenshot: \(error.localizedDescription)",
      )
    }

    // Convert to PNG data
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
      throw MCPError.internalError("Failed to encode screenshot as PNG.")
    }

    // Save to disk if requested
    if let savePath {
      let url = URL(fileURLWithPath: savePath)
      do {
        try pngData.write(to: url)
      } catch {
        throw MCPError.internalError(
          "Failed to save screenshot to '\(savePath)': \(error.localizedDescription)",
        )
      }
    }

    // Build result
    let base64 = pngData.base64EncodedString()
    let windowInfo = targetWindow.title ?? "untitled"
    let appInfo =
      targetWindow.owningApplication?.applicationName
      ?? targetWindow.owningApplication?.bundleIdentifier ?? "unknown"

    var description =
      "Screenshot of '\(appInfo)' window '\(windowInfo)' (\(cgImage.width)x\(cgImage.height) px)"
    if let savePath {
      description += "\nSaved to: \(savePath)"
    }

    return CallTool.Result(
      content: [
        .image(data: base64, mimeType: "image/png", metadata: nil),
        .text(description),
      ],
    )
  }
}
