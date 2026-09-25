import Foundation
import Testing
@testable import XCMCPCore

/// Checks that `XCStringsFileEncoder` writes the same bytes as Xcode's `xcstringstool sync` for the
/// same catalog. Ported from Ryu0118/xcstrings-crud@78b31d0. The suite skips when `xcrun` cannot
/// find `xcstringstool`, for example on a machine without Xcode.
@Suite(
    .temporaryDirectory,
    .enabled("requires xcstringstool") {
        try await ProcessResult.xcrun("--find", arguments: ["xcstringstool"]).exitCode == 0
    }
)
struct XCStringsXcodeParityTests {
    @Test(arguments: ParityCatalog.all)
    func `encoder output matches the xcstringstool rewrite of the same catalog`(
        catalog: ParityCatalog
    ) async throws {
        let workDir = TemporaryDirectory.url
        let catalogURL = workDir.appendingPathComponent("\(catalog.tableName).xcstrings")
        let stringsdataURL = workDir.appendingPathComponent("Sentinel.stringsdata")
        try XCStringsFileEncoder.encode(catalog.file).write(to: catalogURL)

        // `sync` rewrites the catalog only when the stringsdata changes it, so the stringsdata
        // adds one key that the catalog does not hold yet
        let sentinelKey = "zz sentinel"
        let stringsdata = """
            {"source":"/tmp/\(catalog.tableName).swift","tables":{"\(catalog.tableName)":[\
            {"comment":"","key":"\(sentinelKey)","location":{"startingColumn":1,"startingLine":1}}\
            ]},"version":1}
            """
        try Data(stringsdata.utf8).write(to: stringsdataURL)

        let result = try await ProcessResult.xcrun(
            "xcstringstool",
            arguments: [
                "sync", catalogURL.path, "--stringsdata", stringsdataURL.path,
                "--skip-marking-strings-stale",
            ]
        )
        try #require(result.exitCode == 0, "xcstringstool sync failed: \(result.stderr)")

        var expectedFile = catalog.file
        expectedFile.strings[sentinelKey] = StringEntry()
        let xcodeOutput = try Data(contentsOf: catalogURL)
        let encoderOutput = try XCStringsFileEncoder.encode(expectedFile)

        if xcodeOutput != encoderOutput {
            Issue.record("\(Self.diffDescription(expected: xcodeOutput, actual: encoderOutput))")
        }
    }

    /// Describes the first byte where the encoder output leaves the xcstringstool output, with
    /// 40 bytes of context on each side.
    private static func diffDescription(expected: Data, actual: Data) -> String {
        // both buffers come from Data(contentsOf:) or the encoder, so their indices start at 0
        let common = min(expected.count, actual.count)
        let mismatch = (0 ..< common).first { expected[$0] != actual[$0] } ?? common

        func context(_ bytes: Data) -> String {
            let slice = bytes[max(0, mismatch - 40) ..< min(bytes.count, mismatch + 40)]
            return String(bytes: slice, encoding: .utf8) ?? "<non-UTF-8 bytes: \(Array(slice))>"
        }

        return """
            Output leaves xcstringstool at byte offset \(mismatch) \
            (xcstringstool length: \(expected.count), encoder length: \(actual.count)).
            xcstringstool: \(context(expected))
            encoder:       \(context(actual))
            """
    }
}

/// A catalog for the parity test. The table name also names the test case.
struct ParityCatalog: CustomTestStringConvertible, Sendable {
    let tableName: String
    let file: XCStringsFile

    var testDescription: String { tableName }

    static let all = [
        ParityCatalog(tableName: "MixedKeys", file: mixedKeys),
        ParityCatalog(tableName: "PluralCatalog", file: plural),
    ]

    private static func unit(_ value: String) -> Localization {
        Localization(stringUnit: StringUnit(value: value))
    }

    /// ASCII and non-ASCII keys, mixed case, numeric suffixes, escapes, `shouldTranslate: false`,
    /// an empty entry, and an empty `localizations` object.
    private static var mixedKeys: XCStringsFile {
        var strings: [String: StringEntry] = [:]
        let keys = [
            "-x", "_x", "~x", "f", "B upper", "b lower", "Key10", "Key2", "Z", "a",
            "product.type.11_1", "product.type.12_1", "product.type.1_1", "product.type.2_1",
            "e\u{301}b", "\u{E9}", "\u{E9}a", "\u{3C9}", "\u{65E5}\u{672C}", "\u{FF41}", "\u{FF5E}",
            "\u{1F600}", "\u{1F600}x",
        ]
        for key in keys {
            strings[key] = StringEntry(localizations: ["en": unit("Value for \(key)")])
        }
        strings["Domestic / Foreign"] = StringEntry(localizations: [
            "en": unit("Value with \"quotes\"\nand a newline")
        ])
        strings["BrandName"] = StringEntry(comment: "Product name", shouldTranslate: false)
        strings["EmptyEntry"] = StringEntry()
        // XCStringsWriter leaves `localizations: [:]` after it deletes a key's last language
        strings["EmptyLocalizations"] = StringEntry(localizations: [:])
        return XCStringsFile(strings: strings)
    }

    private static var plural: XCStringsFile {
        let variations = Variations(plural: PluralVariation(
            one: VariationValue(stringUnit: StringUnit(value: "%lld item")),
            other: VariationValue(stringUnit: StringUnit(value: "%lld items"))
        ))
        return XCStringsFile(strings: [
            "%lld items": StringEntry(localizations: ["en": Localization(variations: variations)])
        ])
    }
}
