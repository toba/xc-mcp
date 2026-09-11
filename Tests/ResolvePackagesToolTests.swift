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

    private static func unreplaced(
        _ identity: String,
        pinned state: String = "3.9.2",
        requirement: DeclaredRequirement? = nil,
    ) -> ResolvePackagesTool.UnreplacedPin {
        .init(identity: identity, pinnedState: state, requirement: requirement)
    }

    private static func declared(
        _ requirement: String,
        file: String,
        source: DeclaredRequirement.Source,
        admission: DeclaredRequirement.Admission,
    ) -> DeclaredRequirement {
        .init(
            identity: "toba-data", requirement: requirement, file: file, source: source,
            admission: admission,
        )
    }

    @Test
    func `A restored pins file reports that no version moved`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [Self.unreplaced("toba-data")], restored: true,
        )

        #expect(message.contains("toba-data"))
        #expect(message.contains("restored to its prior state"))
        #expect(!message.contains("WARNING"))
    }

    @Test
    func `A pins file that could not be restored warns`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [Self.unreplaced("toba-data")], restored: false,
        )

        #expect(message.contains("WARNING"))
        #expect(message.contains("version control"))
    }

    @Test
    func `A requirement that still admits the pin names it and drops the checkout remedy`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [
                Self.unreplaced(
                    "toba-data",
                    pinned: "1.2.1",
                    requirement: Self.declared(
                        "from: 1.2.0", file: "/repo/App.xcodeproj", source: .project,
                        admission: .admits,
                    ),
                )
            ],
            restored: true,
        )

        #expect(message.contains("from: 1.2.0"))
        #expect(message.contains("/repo/App.xcodeproj"))
        #expect(message.contains("update_swift_package"))
        #expect(!message.contains("DerivedData"))
    }

    @Test
    func `A requirement in a local package's manifest names that manifest`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [
                Self.unreplaced(
                    "toba-data",
                    pinned: "1.2.1",
                    requirement: Self.declared(
                        "from: 1.2.0", file: "/repo/Package.swift", source: .manifest,
                        admission: .admits,
                    ),
                )
            ],
            restored: true,
        )

        #expect(message.contains("/repo/Package.swift"))
        #expect(message.contains("local package's manifest"))
        #expect(!message.contains("DerivedData"))
    }

    @Test
    func `A requirement that excludes the pin points at the cached copy`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [
                Self.unreplaced(
                    "toba-data",
                    pinned: "1.2.1",
                    requirement: Self.declared(
                        "from: 2.0.0", file: "/repo/Package.swift", source: .manifest,
                        admission: .excludes,
                    ),
                )
            ],
            restored: true,
        )

        #expect(message.contains("from: 2.0.0"))
        #expect(message.contains("a cached copy is the reason"))
    }

    @Test
    func `A package no file in reach declares points at the cached copy`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [Self.unreplaced("toba-data", pinned: "1.2.1")], restored: true,
        )

        #expect(message.contains("no project or manifest in reach"))
        #expect(message.contains("older than the published tag"))
    }

    // MARK: - Naming the caches

    private static let cache = SourcePackagesCache(
        directory: "/Caches/xc-mcp/DerivedData/Jig-abc123-macosx/SourcePackages")

    @Test
    func `A failure names all three caches for each unpinned package`() {
        let message = ResolvePackagesTool.unreplacedPinsMessage(
            [Self.unreplaced("toba-data")],
            restored: true,
            cacheNotes: ResolvePackagesTool.cacheNotes(
                cache: Self.cache, identities: ["toba-data"], cleared: false,
            ),
        )

        #expect(message.contains("SourcePackages/checkouts/toba-data"))
        #expect(message.contains("SourcePackages/repositories/toba-data-<hash>"))
        #expect(message.contains("org.swift.swiftpm/repositories/toba-data-<hash>"))
        #expect(message.contains("may need to go"))
    }

    @Test
    func `A failure after the tree was cleared rules the caches out`() {
        let notes = ResolvePackagesTool.cacheNotes(
            cache: Self.cache, identities: ["toba-data"], cleared: true,
        )

        #expect(notes[0].contains("was cleared and the resolve ran again"))
        #expect(notes[0].contains("stale copy is not the reason"))
        #expect(notes.count == 4)
    }

    @Test
    func `A failure with no tree to name adds no cache lines`() {
        #expect(
            ResolvePackagesTool
                .cacheNotes(
                    cache: nil, identities: ["toba-data"], cleared: false
                ).isEmpty)
    }
}
