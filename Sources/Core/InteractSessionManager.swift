import ApplicationServices
import Foundation

/// Caches AXUIElement references between interact tool calls.
///
/// Elements are keyed by PID. The array index is the element ID returned by `interact_ui_tree`.
/// Subsequent tools look up elements by ID from this cache.
public actor InteractSessionManager {
    public static let shared = InteractSessionManager()

    private var cache: [pid_t: [SendableAXUIElement]] = [:]

    private init() {}

    /// Caches elements for a given PID. Replaces any existing cache for that PID.
    public func cacheElements(pid: pid_t, elements: [SendableAXUIElement]) {
        cache[pid] = elements
    }

    /// Retrieves a cached element by PID and element ID.
    public func getElement(pid: pid_t, elementId: Int) -> SendableAXUIElement? {
        guard let pidCache = cache[pid], elementId >= 0, elementId < pidCache.count else {
            return nil
        }
        return pidCache[elementId]
    }

    /// Returns whether a cache exists for the given PID.
    public func hasCache(pid: pid_t) -> Bool {
        cache[pid] != nil
    }

    /// Invalidates the cache for a given PID.
    public func invalidateCache(pid: pid_t) {
        cache.removeValue(forKey: pid)
    }

    /// Returns the number of cached elements for a PID.
    public func elementCount(pid: pid_t) -> Int {
        cache[pid]?.count ?? 0
    }
}
