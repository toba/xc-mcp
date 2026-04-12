import AppKit
import CoreGraphics
import Foundation
import MCP

/// Fast macOS window capture using CGWindowList + `screencapture`.
///
/// Replaces ScreenCaptureKit which can hang 20+ seconds on
/// `SCShareableContent.excludingDesktopWindows()` (macOS 26).
public enum WindowCapture {
    /// Metadata about a matched window.
    public struct WindowInfo: Sendable {
        public let windowID: CGWindowID
        public let ownerName: String?
        public let windowName: String?
    }

    /// Finds the first on-screen window matching the given criteria.
    ///
    /// At least one of the parameters must be non-nil. All non-nil criteria
    /// must match (AND logic). Matching is case-insensitive substring.
    ///
    /// - Parameters:
    ///   - appName: Match against the window owner's application name.
    ///   - bundleId: Match against the owning application's bundle identifier.
    ///   - windowTitle: Match against the window's title.
    /// - Returns: Info about the first matching window.
    /// - Throws: ``MCPError`` if enumeration fails or no window matches.
    public static func findWindow(
        appName: String? = nil,
        bundleId: String? = nil,
        windowTitle: String? = nil,
    ) throws(MCPError) -> WindowInfo {
        guard
            let windowInfoList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID,
            ) as? [[String: Any]]
        else {
            throw .internalError(
                "Failed to get window list. Ensure Screen Recording permission is granted in "
                    + "System Settings > Privacy & Security > Screen Recording.",
            )
        }

        // Build PID → bundle ID cache when needed
        var bundleIDsByPID: [pid_t: String] = [:]
        if bundleId != nil {
            for app in NSWorkspace.shared.runningApplications {
                if let id = app.bundleIdentifier {
                    bundleIDsByPID[app.processIdentifier] = id
                }
            }
        }

        for info in windowInfoList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if let appName {
                guard
                    let name = info[kCGWindowOwnerName as String] as? String,
                    name.localizedCaseInsensitiveContains(appName)
                else { continue }
            }
            if let bundleId {
                guard
                    let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                    let id = bundleIDsByPID[pid],
                    id.localizedCaseInsensitiveContains(bundleId)
                else { continue }
            }
            if let windowTitle {
                guard
                    let title = info[kCGWindowName as String] as? String,
                    title.localizedCaseInsensitiveContains(windowTitle)
                else { continue }
            }
            return WindowInfo(
                windowID: wid,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                windowName: info[kCGWindowName as String] as? String,
            )
        }

        var criteria: [String] = []
        if let appName { criteria.append("app_name='\(appName)'") }
        if let bundleId { criteria.append("bundle_id='\(bundleId)'") }
        if let windowTitle { criteria.append("window_title='\(windowTitle)'") }
        throw .invalidParams(
            "No window found matching \(criteria.joined(separator: ", ")). "
                + "Make sure the app is running and has a visible window.",
        )
    }

    /// Captures a window as PNG data using `screencapture -l`.
    ///
    /// - Parameters:
    ///   - windowID: The CGWindowID to capture.
    ///   - savePath: If provided, the PNG is written here and kept on disk.
    ///     Otherwise a temp file is used and cleaned up.
    /// - Returns: The raw PNG data.
    public static func capture(
        windowID: CGWindowID,
        savePath: String? = nil,
    ) async throws(MCPError) -> Data {
        let outputPath =
            savePath
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("xc-mcp-capture-\(windowID).png").path

        let result: ProcessResult
        do {
            result = try await ProcessResult.run(
                "/usr/sbin/screencapture",
                arguments: ["-l", "\(windowID)", "-x", outputPath],
                timeout: .seconds(10),
            )
        } catch {
            throw .internalError("screencapture failed: \(error.localizedDescription)")
        }
        guard result.succeeded else {
            throw .internalError(
                "screencapture failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        let pngData: Data
        do {
            pngData = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        } catch {
            throw .internalError(
                "Failed to read screenshot file: \(error.localizedDescription)",
            )
        }

        if savePath == nil {
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        return pngData
    }
}
