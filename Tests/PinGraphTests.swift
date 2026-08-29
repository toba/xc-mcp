import Testing
import Foundation
@testable import XCMCPCore

@Suite("Pin graph")
struct PinGraphTests {
    /// The chain a toba-core release walks: core, then hash, then data, then jig.
    static let workspace: [String: Set<String>] = [
        "toba-core": [],
        "toba-hash": ["toba-core"],
        "toba-data": ["toba-core", "toba-hash"],
        "jig": ["toba-core", "toba-data"],
    ]

    @Test func `puts every dependency before the members that pin it`() throws {
        let order = try PinGraph.topologicalOrder(Self.workspace)
        #expect(order == ["toba-core", "toba-hash", "toba-data", "jig"])
    }

    @Test func `ignores an edge naming a package outside the member list`() throws {
        let order = try PinGraph.topologicalOrder([
            "toba-core": ["swift-syntax"],
            "toba-hash": ["toba-core", "swift-syntax"],
        ])
        #expect(order == ["toba-core", "toba-hash"])
    }

    @Test func `orders independent members by name`() throws {
        let order = try PinGraph.topologicalOrder([
            "toba-xml": ["toba-core"],
            "toba-hash": ["toba-core"],
            "toba-core": [],
        ])
        #expect(order == ["toba-core", "toba-hash", "toba-xml"])
    }

    @Test func `refuses a cycle and names the members in it`() {
        #expect(throws: PinGraph.Cycle(identities: ["toba-settings", "toba-ui"])) {
            try PinGraph.topologicalOrder([
                "toba-core": [],
                "toba-settings": ["toba-ui"],
                "toba-ui": ["toba-settings", "toba-core"],
            ])
        }
    }

    @Test func `orders an empty graph`() throws {
        #expect(try PinGraph.topologicalOrder([:]).isEmpty)
    }
}

@Suite("Version bump")
struct VersionBumpTests {
    @Test func `a minor bump clears the patch`() {
        #expect(VersionBump.minor.next(after: SemanticVersion("2.0.6")!).description == "2.1.0")
    }

    @Test func `a major bump clears the minor and the patch`() {
        #expect(VersionBump.major.next(after: SemanticVersion("1.13.3")!).description == "2.0.0")
    }

    @Test func `a patch bump advances the patch alone`() {
        #expect(VersionBump.patch.next(after: SemanticVersion("1.13.3")!).description == "1.13.4")
    }

    @Test func `a bump drops a prerelease identifier`() {
        #expect(
            VersionBump.patch.next(after: SemanticVersion("1.2.0-beta.1")!).description == "1.2.1",
        )
    }
}
