import XCTest
@testable import XCMCPCore

/// Timing floor for the in-place batch write (jig dea1cdfc).
///
/// Writing by value copied the whole `strings` dictionary once per entry, so the cost grew with the
/// product of the catalog size and the batch size. `measure` is the only sanctioned timer here, and
/// a recorded baseline is what turns a return of that shape into a failure.
final class XCStringsBatchWritePerfTests: XCTestCase {
    private static let keyCount = 2000

    private static func catalog() -> XCStringsFile {
        var strings: [String: StringEntry] = [:]
        strings.reserveCapacity(keyCount)

        for index in 0..<keyCount {
            strings["key_\(index)"] = StringEntry(localizations: [
                "en": Localization(stringUnit: StringUnit(value: "value \(index)"))
            ])
        }
        return .init(strings: strings)
    }

    private static func batch() -> [BatchTranslationEntry] {
        (0..<keyCount).map {
            BatchTranslationEntry(key: "key_\($0)", translations: ["fr": "valeur \($0)"])
        }
    }

    func testBatchAddScalesWithTheBatchNotTheCatalog() {
        let file = Self.catalog()
        let entries = Self.batch()

        measure {
            let (updated, result) = XCStringsWriter.addTranslationsBatch(to: file, entries: entries)
            XCTAssertEqual(result.succeeded, Self.keyCount)
            XCTAssertEqual(updated.strings.count, Self.keyCount)
        }
    }
}
