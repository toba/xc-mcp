import Foundation
import CoreGraphics

/// One on-screen window from `CGWindowListCopyWindowInfo`, with the untyped `[String: Any]` info
/// dictionary decoded into typed fields at the framework boundary.
struct WindowEntry: Sendable {
    let id: CGWindowID
    let ownerName: String?
    let ownerPID: pid_t?
    let windowName: String?
    /// Window bounds in global display points (top-left origin), or `nil` if unavailable.
    let bounds: CGRect?
}

/// Typed wrapper over `CGWindowListCopyWindowInfo`, shared by the window-capture and simulator
/// input paths so the `[String: Any]` decoding lives in one place.
enum WindowList {
    /// Enumerates on-screen windows (excluding desktop elements), or `nil` when the window list
    /// can't be obtained — typically because Screen Recording permission hasn't been granted.
    ///
    /// Entries without a window number are dropped; every real window has one.
    static func onScreen() -> [WindowEntry]? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID,
        ) as? [[String: Any]] else { return nil }

        return list.compactMap { info -> WindowEntry? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            let bounds = (info[kCGWindowBounds as String] as? [String: CGFloat]).flatMap {
                b -> CGRect? in
                guard let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
                else { return nil }
                return CGRect(x: x, y: y, width: w, height: h)
            }
            return WindowEntry(
                id: id,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                ownerPID: info[kCGWindowOwnerPID as String] as? pid_t,
                windowName: info[kCGWindowName as String] as? String,
                bounds: bounds,
            )
        }
    }
}
