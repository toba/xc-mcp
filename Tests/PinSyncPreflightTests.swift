import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite("Pin sync preflight")
struct PinSyncPreflightTests {
    static func status(
        branch: String? = "main",
        upstream: String? = "origin/main",
        behind: Int = 0,
        ahead: Int = 0,
        staged: [String] = [],
        unstaged: [String] = [],
        untracked: [String] = [],
    ) -> GitStatus {
        .init(
            branch: branch,
            upstream: upstream,
            behind: behind,
            ahead: ahead,
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
        )
    }

    @Test func `passes a clean tree on a tracking branch`() {
        #expect(PinSyncPreflight.check(Self.status(), of: "toba-core").isEmpty)
    }

    @Test func `blocks a staged change`() {
        let blockers = PinSyncPreflight.check(
            Self.status(staged: ["Sources/Foo.swift"]), of: "toba-core",
        )
        #expect(blockers.count == 1)
        #expect(blockers[0].reason.contains("1 staged change"))
        #expect(blockers[0].reason.contains("Sources/Foo.swift"))
    }

    @Test func `blocks an unstaged change`() {
        let blockers = PinSyncPreflight.check(
            Self.status(unstaged: ["Package.swift"]), of: "toba-hash",
        )
        #expect(blockers.count == 1)
        #expect(blockers[0].reason.contains("1 unstaged change"))
    }

    @Test func `blocks a detached head`() {
        let blockers = PinSyncPreflight.check(Self.status(branch: nil), of: "toba-core")
        #expect(blockers.contains { $0.reason.contains("detached") })
    }

    @Test func `blocks a branch that tracks no remote`() {
        let blockers = PinSyncPreflight.check(Self.status(upstream: nil), of: "toba-core")
        #expect(blockers.contains { $0.reason.contains("tracks no remote branch") })
    }

    @Test func `blocks a branch behind its remote`() {
        let blockers = PinSyncPreflight.check(Self.status(behind: 2), of: "toba-core")
        #expect(blockers.contains { $0.reason.contains("2 commits behind origin/main") })
    }

    @Test func `blocks unpushed commits`() {
        let blockers = PinSyncPreflight.check(Self.status(ahead: 1), of: "toba-core")
        #expect(blockers.contains { $0.reason.contains("1 unpushed commit") })
    }

    @Test func `allows an untracked file`() {
        #expect(PinSyncPreflight.check(Self.status(untracked: ["notes.txt"]), of: "jig").isEmpty)
    }

    @Test func `truncates a long list of changed paths`() {
        let paths = (1...5).map { "Sources/File\($0).swift" }
        let blockers = PinSyncPreflight.check(Self.status(staged: paths), of: "toba-core")
        #expect(blockers[0].reason.contains("and 2 more"))
    }

    @Test func `reports every blocker a tree carries at once`() {
        let blockers = PinSyncPreflight.check(
            Self.status(behind: 1, ahead: 1, staged: ["a"], unstaged: ["b"]), of: "toba-core",
        )
        #expect(blockers.count == 4)
    }
}
