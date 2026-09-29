import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Tests for the in-process `.dia` decoder that replaces `c-index-test`.
///
/// `sample-diagnostics.dia` comes from `swiftc -typecheck` on a file with a redeclared function and
/// an undefined name, so it holds two errors and one note.
struct SerializedDiagnosticsTests {
    private func fixture() throws -> [UInt8] {
        try Array(Data(contentsOf: TestFixtures.url("sample-diagnostics.dia")))
    }

    @Test
    func `a swift-frontend dia file decodes to its errors and notes`() throws {
        let diagnostics = try SerializedDiagnostics.decode(fixture())

        #expect(diagnostics.count == 2)

        let redeclaration = try #require(diagnostics.first)
        #expect(redeclaration.severity == .error)
        #expect(redeclaration.message == "invalid redeclaration of 'g()'")
        #expect(redeclaration.file?.hasSuffix("Sample.swift") == true)
        #expect(redeclaration.line == 2)
        #expect(redeclaration.column == 6)
        #expect(redeclaration.notes.count == 1)
        #expect(redeclaration.notes.first?.severity == .note)
        #expect(redeclaration.notes.first?.message == "'g()' previously declared here")

        let undefined = try #require(diagnostics.last)
        #expect(undefined.message == "cannot find 'undefinedName' in scope")
        #expect(undefined.line == 6)
        #expect(undefined.column == 5)
    }

    @Test
    func `a decoded diagnostic prints in compiler form with its note indented`() throws {
        let text = try #require(SerializedDiagnostics.decode(fixture()).first).formatted()

        #expect(text.contains("Sample.swift:2:6: error: invalid redeclaration of 'g()'"))
        #expect(text.contains("\n  "))
        #expect(text.contains("note: 'g()' previously declared here"))
    }

    @Test
    func `bytes without the DIAG magic are rejected`() {
        #expect(throws: SerializedDiagnostics.DecodeError.notSerializedDiagnostics) {
            try SerializedDiagnostics.decode(Array("not a dia".utf8))
        }
    }

    @Test
    func `a truncated file throws instead of trapping`() throws {
        // Dropping the last two words cuts the final diagnostic block before its END_BLOCK.
        let bytes = try fixture()
        #expect(throws: SerializedDiagnostics.DecodeError.self) {
            try SerializedDiagnostics.decode(Array(bytes.dropLast(8)))
        }
    }

    @Test
    func `record text keeps a message that holds an invalid UTF-8 byte`() {
        let valid = Array("cannot find 'x'".utf8)
        #expect(SerializedDiagnostics.Record.decodeUTF8(valid) == "cannot find 'x'")

        let invalid = Array("bad ".utf8) + [0xFF] + Array(" byte".utf8)
        #expect(SerializedDiagnostics.Record.decodeUTF8(invalid) == "bad \u{FFFD} byte")
    }

    @Test
    func `a byte search finds a message without a decode`() {
        let path = TestFixtures.url("sample-diagnostics.dia").path
        #expect(SerializedDiagnostics.fileContains("undefinedName", atPath: path))
        #expect(!SerializedDiagnostics.fileContains("reproducer is available", atPath: path))
    }
}
