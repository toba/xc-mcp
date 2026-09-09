import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite
struct ResolvePackagesToolTests {
    private static func pin(_ identity: String, _ version: String) -> ResolvedPin {
        .init(identity: identity, location: "https://github.com/toba/\(identity)", version: version)
    }

    @Test
    func `A pin resolution never wrote back counts as unreplaced`() {
        let before = [
            "toba-data": Self.pin("toba-data", "3.9.2"),
            "toba-core": Self.pin("toba-core", "1.4.0"),
        ]
        let after = ["toba-core": Self.pin("toba-core", "1.4.0")]

        #expect(ResolvePackagesTool.unreplacedPins(before: before, after: after) == ["toba-data"])
    }

    @Test
    func `A pin resolution moved to a newer version is not unreplaced`() {
        let before = ["toba-markdown": Self.pin("toba-markdown", "1.0.0")]
        let after = ["toba-markdown": Self.pin("toba-markdown", "1.0.1")]

        #expect(ResolvePackagesTool.unreplacedPins(before: before, after: after).isEmpty)
    }

    @Test
    func `A pin resolution added is not unreplaced`() {
        let before = ["toba-core": Self.pin("toba-core", "1.4.0")]
        let after = [
            "toba-core": Self.pin("toba-core", "1.4.0"),
            "toba-hash": Self.pin("toba-hash", "2.0.0"),
        ]

        #expect(ResolvePackagesTool.unreplacedPins(before: before, after: after).isEmpty)
    }

    @Test
    func `A restored pins file reports that no version moved`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(["toba-data"], restored: true)

        #expect(message.contains("toba-data"))
        #expect(message.contains("restored to its prior state"))
        #expect(!message.contains("WARNING"))
    }

    @Test
    func `A pins file that could not be restored warns`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(["toba-data"], restored: false)

        #expect(message.contains("WARNING"))
        #expect(message.contains("version control"))
    }
}
