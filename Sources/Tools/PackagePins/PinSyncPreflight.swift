import XCMCPCore
import Foundation

/// One reason a member cannot take part in a sweep
public struct PinSyncBlocker: Sendable, Equatable {
    /// The member's directory name
    public let member: String

    /// What stops the sweep, in one sentence
    public let reason: String

    public init(member: String, reason: String) {
        self.member = member
        self.reason = reason
    }
}

/// Checks every member before the sweep writes to any member
///
/// The sweep publishes one layer before the next layer edits, so a member that fails halfway leaves
/// the layers above it pinning a tag that was never pushed. Checking all of them first is what
/// keeps the run all-or-nothing.
public enum PinSyncPreflight {
    /// Reports every reason a member cannot take part.
    ///
    /// - Parameters:
    ///   - member: The loaded member.
    ///   - git: The git runner.
    /// - Returns: The blockers found, empty when the member is ready.
    public static func check(
        _ member: PinSyncMember,
        git: GitRunner,
    ) async -> [PinSyncBlocker] {
        var blockers: [PinSyncBlocker] = []

        for manifest in member.manifests {
            for path in manifest.localPaths {
                blockers.append(.init(
                    member: member.name,
                    reason: "\(manifest.relativePath) declares a local path dependency on "
                        + "'\(path)', so its release would build a working tree nobody else has",
                ))
            }
        }

        let root: String?

        do {
            root = try await git.workTreeRoot(containing: member.root)
        } catch {
            blockers.append(.init(member: member.name, reason: "git cannot read it: \(error)"))
            return blockers
        }

        guard let root else {
            blockers.append(.init(member: member.name, reason: "sits in no git repository"))
            return blockers
        }
        guard URL(fileURLWithPath: root).standardized
            .path
            == URL(fileURLWithPath: member.root).standardized.path
        else {
            blockers.append(.init(
                member: member.name,
                reason: "is not a repository root. Its work tree starts at \(root)",
            ))
            return blockers
        }

        let status: GitStatus

        do {
            status = try await git.status(repository: member.root)
        } catch {
            blockers.append(.init(member: member.name, reason: "git status failed: \(error)"))
            return blockers
        }
        blockers.append(contentsOf: check(status, of: member.name))
        return blockers
    }

    /// Reports the blockers a working-tree status carries.
    static func check(_ status: GitStatus, of member: String) -> [PinSyncBlocker] {
        var blockers: [PinSyncBlocker] = []

        func add(_ reason: String) { blockers.append(.init(member: member, reason: reason)) }

        if !status.staged.isEmpty {
            add("has \(count(status.staged, "staged change")): \(list(status.staged))")
        }

        if !status.unstaged.isEmpty {
            add("has \(count(status.unstaged, "unstaged change")): \(list(status.unstaged))")
        }

        guard let branch = status.branch else {
            add("has a detached HEAD, so a commit would land on no branch")
            return blockers
        }

        guard let upstream = status.upstream else {
            add("is on '\(branch)', which tracks no remote branch, so the push has no target")
            return blockers
        }
        if status.behind > 0 {
            add(
                "is \(count(status.behind, "commit")) behind \(upstream), so the push would be "
                    + "rejected")
        }
        if status.ahead > 0 {
            add(
                "holds \(count(status.ahead, "unpushed commit")), which the sweep's push would "
                    + "publish alongside the pin change")
        }
        return blockers
    }

    /// Renders a count with a singular or plural noun.
    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private static func count(_ items: [String], _ noun: String) -> String {
        count(items.count, noun)
    }

    /// Renders at most the first three paths, so one broken member cannot flood the report.
    private static func list(_ paths: [String]) -> String {
        let shown = paths.prefix(3).joined(separator: ", ")
        return paths.count > 3 ? shown + ", and \(paths.count - 3) more" : shown
    }
}
