import Foundation

/// Shared post-action handling for mutating `interact_*` tools.
///
/// After a mutating action the UI may still be animating or recomposing, which leaves the
/// element cache from the previous `interact_ui_tree` call stale. This helper waits for the
/// accessibility tree to settle, refreshes the cache with the new element references, and
/// returns a formatted snapshot to append to the tool's response so the next agent step
/// receives stable element IDs without a separate `interact_ui_tree` call.
public enum InteractPostAction {
    /// Settles the UI, refreshes the cached element refs for `pid`, and returns a formatted
    /// tree snapshot suitable for appending to a mutating tool's text response.
    public static func settledSnapshot(
        runner: InteractRunner,
        pid: pid_t,
        maxDepth: Int = 3,
    ) async throws -> String {
        let tree = try await runner.settledUITree(pid: pid, maxDepth: maxDepth)
        await InteractSessionManager.shared.cacheElements(pid: pid, elements: tree.map(\.1))

        var lines: [String] = []
        lines.reserveCapacity(tree.count + 2)
        lines.append("")
        lines.append("UI tree after action (settled, \(tree.count) elements):")
        for (element, _) in tree { lines.append(element.summary()) }
        return lines.joined(separator: "\n")
    }
}
