import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the escape-sequence stripper that keeps color codes out of a reported diagnostic.
struct TerminalEscapesTests {
    /// The escape byte, spelled once so a test reads as the text a terminal receives.
    private let escape = "\u{1B}"

    @Test
    func `plain text comes back unchanged`() {
        let line = "Sources/Foo.swift:12:5: error: cannot convert 'Int' to 'String'"

        #expect(TerminalEscapes.stripped(line) == line)
    }

    @Test
    func `a colored diagnostic keeps its path, its position and its message`() {
        let line = "\(escape)[0;1mSources/Foo.swift:12:5: \(escape)[0;1;31merror: "
            + "\(escape)[0mcannot convert 'Int' to 'String'\(escape)[0m"

        #expect(
            TerminalEscapes.stripped(
                line)
                == "Sources/Foo.swift:12:5: error: cannot convert 'Int' to 'String'",
        )
    }

    @Test
    func `a parameterless control sequence goes with its escape`() {
        #expect(TerminalEscapes.stripped("before\(escape)[Kafter") == "beforeafter")
    }

    @Test
    func `an operating system command ends on a bell`() {
        #expect(TerminalEscapes.stripped("\(escape)]0;title\u{07}text") == "text")
    }

    @Test
    func `an operating system command ends on a string terminator`() {
        #expect(
            TerminalEscapes.stripped("\(escape)]8;;https://example.com\(escape)\\link") == "link")
    }

    @Test
    func `a two-byte escape loses both bytes`() {
        // ESC 7 saves the cursor position
        #expect(TerminalEscapes.stripped("a\(escape)7b") == "ab")
    }

    @Test
    func `an escape that ends the text drops cleanly`() {
        #expect(TerminalEscapes.stripped("tail\(escape)") == "tail")
        #expect(TerminalEscapes.stripped("tail\(escape)[0;1") == "tail")
    }

    @Test
    func `text outside ASCII survives the strip`() {
        #expect(TerminalEscapes.stripped("\(escape)[1m✗ tëst 􀄵\(escape)[0m") == "✗ tëst 􀄵")
    }

    @Test
    func `a colored error line parses into a file, a position and a message`() {
        let parser = BuildOutputParser()
        let input = "\(escape)[0;1m/pkg/Sources/Foo.swift:42:10: \(escape)[0;1;31merror: "
            + "\(escape)[0mcannot find 'bar' in scope\(escape)[0m"

        let result = parser.parse(input: input)

        #expect(result.errors.count == 1)
        #expect(result.errors[0].file == "/pkg/Sources/Foo.swift")
        #expect(result.errors[0].line == 42)
        #expect(result.errors[0].column == 10)
        #expect(result.errors[0].message == "cannot find 'bar' in scope")
    }

    @Test
    func `errors in several files are all reported`() {
        let parser = BuildOutputParser()
        let input = """
            \(escape)[0;1m/pkg/Sources/A.swift:1:1: \(escape)[0;1;31merror: \(escape)[0mfirst\(escape)[0m
            \(escape)[0;1m/pkg/Sources/B.swift:2:2: \(escape)[0;1;31merror: \(escape)[0msecond\(escape)[0m
            """

        let result = parser.parse(input: input)

        #expect(result.errors.map(\.file) == ["/pkg/Sources/A.swift", "/pkg/Sources/B.swift"])
        #expect(result.summary.errors == 2)
    }
}
