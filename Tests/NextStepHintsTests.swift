import Foundation
import Testing
@testable import XCMCPCore

/// Coverage for the next-step hints helper ported from
/// getsentry/XcodeBuildMCP PR #420.
struct NextStepHintsTests {
    @Test func `render returns nil for empty hints`() {
        #expect(NextStepHints.render([]) == nil)
    }

    @Test func `render sorts by priority ascending and numbers entries`() throws {
        let hints = [
            NextStepHint(label: "C", tool: "tool_c", priority: 3),
            NextStepHint(label: "A", tool: "tool_a", priority: 1),
            NextStepHint(label: "B", tool: "tool_b", priority: 2),
        ]
        let output = try #require(NextStepHints.render(hints))
        let aIdx = try #require(output.range(of: "1. A:"))
        let bIdx = try #require(output.range(of: "2. B:"))
        let cIdx = try #require(output.range(of: "3. C:"))
        #expect(aIdx.lowerBound < bIdx.lowerBound)
        #expect(bIdx.lowerBound < cIdx.lowerBound)
        #expect(output.hasPrefix("Next steps:\n"))
    }

    @Test func `render emits JSON-escaped string params`() throws {
        let hint = NextStepHint(
            label: "Add breakpoint",
            tool: "debug_breakpoint_add",
            params: [
                ("pid", .int(1234)),
                ("file", .string("/tmp/foo bar.swift")),
                ("line", .int(42)),
            ],
        )
        let output = try #require(NextStepHints.render([hint]))
        #expect(output.contains(
            "debug_breakpoint_add({ pid: 1234, file: \"/tmp/foo bar.swift\", line: 42 })"
        ))
    }

    @Test func `render escapes quotes in string params`() throws {
        let hint = NextStepHint(
            label: "Quoted",
            tool: "t",
            params: [("path", .string("he said \"hi\""))],
        )
        let output = try #require(NextStepHints.render([hint]))
        #expect(output.contains("\\\"hi\\\""))
    }

    @Test func `appended preserves message and adds spacer`() {
        let original = "All good."
        let hints = [NextStepHint(label: "Next", tool: "do_thing")]
        let result = NextStepHints.appended(to: original, hints: hints)
        #expect(result.hasPrefix("All good.\n\nNext steps:"))
        #expect(result.contains("do_thing({})"))
    }

    @Test func `appended is identity when no hints`() {
        let original = "Done."
        #expect(NextStepHints.appended(to: original, hints: []) == original)
    }
}
