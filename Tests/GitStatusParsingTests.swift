import Testing
import Foundation
@testable import XCMCPCore

@Suite("Git status parsing")
struct GitStatusParsingTests {
    static let clean = """
        # branch.oid 6f1c0a9b
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """

    @Test func `reads a clean tree on a tracking branch`() {
        let status = GitRunner.parseStatus(Self.clean)
        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
        #expect(status.isClean)
    }

    @Test func `separates a staged change from an unstaged one`() {
        let output = Self.clean + """

            1 M. N... 100644 100644 100644 aaa bbb Package.swift
            1 .M N... 100644 100644 100644 ccc ddd Sources/Foo.swift
            1 MM N... 100644 100644 100644 eee fff Sources/Bar.swift
            """
        let status = GitRunner.parseStatus(output)
        #expect(status.staged == ["Package.swift", "Sources/Bar.swift"])
        #expect(status.unstaged == ["Sources/Foo.swift", "Sources/Bar.swift"])
        #expect(!status.isClean)
    }

    @Test func `reads the new path of a rename, not the score`() {
        let output = Self.clean + """

            2 R. N... 100644 100644 100644 aaa bbb R100 Sources/New.swift\tSources/Old.swift
            """
        #expect(GitRunner.parseStatus(output).staged == ["Sources/New.swift"])
    }

    @Test func `counts commits ahead and behind`() {
        let output = """
            # branch.head main
            # branch.upstream origin/main
            # branch.ab +2 -3
            """
        let status = GitRunner.parseStatus(output)
        #expect(status.ahead == 2)
        #expect(status.behind == 3)
    }

    @Test func `reports a detached head as no branch`() {
        let status = GitRunner.parseStatus("# branch.head (detached)")
        #expect(status.branch == nil)
        #expect(status.upstream == nil)
    }

    @Test func `collects untracked paths separately`() {
        let output = Self.clean + "\n? notes.txt"
        let status = GitRunner.parseStatus(output)
        #expect(status.untracked == ["notes.txt"])
        #expect(status.isClean)
    }

    @Test func `counts an unmerged path on both sides`() {
        let output = Self.clean + """

            u UU N... 100644 100644 100644 100644 aaa bbb ccc Sources/Conflict.swift
            """
        let status = GitRunner.parseStatus(output)
        #expect(status.staged == ["Sources/Conflict.swift"])
        #expect(status.unstaged == ["Sources/Conflict.swift"])
    }
}
