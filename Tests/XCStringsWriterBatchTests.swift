import Testing
import Foundation
@testable import XCMCPCore

/// Covers the two guarantees the in-place batch write has to keep, and the hand-written JSON string
/// escape that replaced a per-key `JSONEncoder` (jig dea1cdfc).
struct XCStringsWriterBatchTests {
    private static func entry(_ pairs: [String: String]) -> StringEntry {
        .init(localizations: pairs.mapValues { Localization(stringUnit: StringUnit(value: $0)) })
    }

    private static func value(_ file: XCStringsFile, _ key: String, _ language: String) -> String? {
        file.strings[key]?.localizations?[language]?.stringUnit?.value
    }

    // MARK: - Per-entry atomicity

    /// The batch loop mutates one catalog in place, so a rejected entry must apply none of its
    /// languages. By-value writing gave that for free by discarding the returned copy.
    @Test func `a rejected batch entry writes none of its languages`() {
        let file = XCStringsFile(strings: ["greeting": Self.entry(["fr": "Bonjour"])])

        let (updated, result) = XCStringsWriter.addTranslationsBatch(
            to: file,
            entries: [
                // "fr" already exists, so the whole entry is rejected — including "de".
                BatchTranslationEntry(
                    key: "greeting", translations: ["fr": "Salut", "de": "Hallo"]),
                BatchTranslationEntry(key: "farewell", translations: ["en": "Bye"]),
            ],
        )

        #expect(result.succeeded == 1)
        #expect(result.errors.count == 1)
        #expect(result.errors.first?.key == "greeting")
        #expect(Self.value(updated, "greeting", "fr") == "Bonjour")
        #expect(updated.strings["greeting"]?.localizations?["de"] == nil)
        #expect(Self.value(updated, "farewell", "en") == "Bye")
    }

    @Test func `a rejected update leaves the entry as it was`() {
        let file = XCStringsFile(strings: [
            "greeting": Self.entry(["en": "Hello", "fr": "Bonjour"])
        ])

        let (updated, result) = XCStringsWriter.updateTranslationsBatch(
            in: file,
            entries: [
                // "de" is absent, so the "en" change in the same entry must not land either.
                BatchTranslationEntry(key: "greeting", translations: ["en": "Hi", "de": "Hallo"])
            ],
        )

        #expect(result.succeeded == 0)
        #expect(Self.value(updated, "greeting", "en") == "Hello")
    }

    @Test func `a batch applies every accepted entry`() {
        let file = XCStringsFile(strings: ["a": Self.entry(["en": "A"])])

        let (updated, result) = XCStringsWriter.addTranslationsBatch(
            to: file,
            entries: [
                BatchTranslationEntry(key: "a", translations: ["fr": "Ah"]),
                BatchTranslationEntry(key: "b", translations: ["en": "B", "fr": "Bé"]),
            ],
        )

        #expect(result.succeeded == 2)
        #expect(result.errors.isEmpty)
        #expect(Self.value(updated, "a", "en") == "A")
        #expect(Self.value(updated, "a", "fr") == "Ah")
        #expect(Self.value(updated, "b", "fr") == "Bé")
    }

    // MARK: - String escaping

    /// The escape is written out rather than delegated to `JSONEncoder`, so a round trip is the
    /// check that it stays valid JSON for the characters that need a substitution.
    @Test func `the encoder escapes control characters without losing the value`() throws {
        let tricky = "quote \" backslash \\ tab \t newline \n bell \u{07} unit \u{01} é 🙂 a/b"
        let file = XCStringsFile(strings: [tricky: Self.entry(["en": tricky])])

        let data = try XCStringsFileEncoder.encode(file)
        let text = String(decoding: data, as: UTF8.self)
        let decoded = try JSONDecoder().decode(XCStringsFile.self, from: data)

        #expect(Self.value(decoded, tricky, "en") == tricky)
        #expect(decoded.strings[tricky] != nil)
        // Xcode leaves a slash unescaped, and non-ASCII goes through as itself.
        #expect(text.contains("a/b"))
        #expect(text.contains("é 🙂"))
        // A control character with no short form takes the four-digit form.
        #expect(text.contains("\\u0007"))
        #expect(text.contains("\\u0001"))
    }

    @Test func `the encoder escapes a backspace and a form feed`() throws {
        let tricky = "back\u{08}space form\u{0C}feed"
        let file = XCStringsFile(strings: ["k": Self.entry(["en": tricky])])

        let data = try XCStringsFileEncoder.encode(file)
        let decoded = try JSONDecoder().decode(XCStringsFile.self, from: data)

        #expect(Self.value(decoded, "k", "en") == tricky)
    }
}
