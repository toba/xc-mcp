import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

/// Unit tests for `discover_projs` sandbox-boundary behavior, independent of fixtures.
///
/// A symlink inside the scanned tree can resolve to a directory outside the sandbox base. Without a
/// per-entry boundary check the recursive scan would follow it and report bundles from outside the
/// base — see issue whu-g1p (analogous to getsentry/XcodeBuildMCP fix 46b2cf6).
struct DiscoverProjectsSandboxTests {
    private func textContent(_ result: CallTool.Result) -> String {
        guard case let .text(content, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }

    @Test func `symlink escaping base is not followed`() throws {
        // <root>/base holds Inside.xcodeproj and a symlink escape -> <root>/outside,
        // which holds Outside.xcodeproj.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("discover-symlink-\(UUID().uuidString)")
        let base = root.appendingPathComponent("base")
        let outside = root.appendingPathComponent("outside")
        let fm = FileManager.default
        try fm.createDirectory(
            at: base.appendingPathComponent("Inside.xcodeproj"), withIntermediateDirectories: true,
        )
        try fm.createDirectory(
            at: outside.appendingPathComponent("Outside.xcodeproj"),
            withIntermediateDirectories: true,
        )
        defer { try? fm.removeItem(at: root) }

        try fm.createSymbolicLink(
            at: base.appendingPathComponent("escape"), withDestinationURL: outside,
        )

        let tool = DiscoverProjectsTool(pathUtility: PathUtility(basePath: base.path))
        let result = try tool.execute(arguments: ["path": .string(base.path)])
        let content = textContent(result)

        #expect(content.contains("Inside.xcodeproj"))
        #expect(!content.contains("Outside.xcodeproj"))
    }

    @Test func `normal nested discovery still works`() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("discover-nested-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(
            at: base.appendingPathComponent("Sub/Nested.xcodeproj"),
            withIntermediateDirectories: true,
        )
        defer { try? fm.removeItem(at: base) }

        let tool = DiscoverProjectsTool(pathUtility: PathUtility(basePath: base.path))
        let result = try tool.execute(arguments: ["path": .string(base.path)])
        #expect(textContent(result).contains("Nested.xcodeproj"))
    }
}
