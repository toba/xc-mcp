import Testing
import XCMCPCore
import Foundation

@Suite
struct PinMoveTests {
    private static func pin(_ identity: String, _ version: String) -> ResolvedPin {
        .init(identity: identity, location: "https://github.com/toba/\(identity)", version: version)
    }

    // MARK: - Diffing two readings

    @Test
    func `A pin whose version rose reads as an update`() {
        let moves = PinMove.moves(
            from: ["toba-data": Self.pin("toba-data", "3.12.4")],
            to: ["toba-data": Self.pin("toba-data", "3.12.5")],
        )

        #expect(moves == [.updated("toba-data", from: "3.12.4", to: "3.12.5")])
        #expect(moves[0].reportLine == "  ~ toba-data 3.12.4 → 3.12.5")
    }

    @Test
    func `A pin at the same version reports no move`() {
        let pins = ["toba-core": Self.pin("toba-core", "1.4.0")]

        #expect(PinMove.moves(from: pins, to: pins).isEmpty)
    }

    @Test
    func `A pin the resolve added reads as an addition`() {
        let moves = PinMove.moves(from: [:], to: ["toba-hash": Self.pin("toba-hash", "2.0.0")])

        #expect(moves == [.added("toba-hash", to: "2.0.0")])
        #expect(moves[0].reportLine == "  + toba-hash 2.0.0")
    }

    @Test
    func `A pin the resolve dropped reads as a removal that keeps the old state`() {
        let moves = PinMove.moves(from: ["toba-xml": Self.pin("toba-xml", "1.1.0")], to: [:])

        #expect(moves == [.removed("toba-xml", from: "1.1.0")])
        #expect(moves[0].reportLine == "  - toba-xml 1.1.0 (no longer pinned)")
    }

    @Test
    func `Moves list the additions and updates before the removals`() {
        let moves = PinMove.moves(
            from: [
                "toba-data": Self.pin("toba-data", "3.12.4"),
                "toba-xml": Self.pin("toba-xml", "1.1.0"),
            ],
            to: [
                "toba-data": Self.pin("toba-data", "3.12.5"),
                "toba-hash": Self.pin("toba-hash", "2.0.0"),
            ],
        )

        #expect(moves.map(\.name) == ["toba-data", "toba-hash", "toba-xml"])
        #expect(moves.map(\.kind) == [.updated, .added, .removed])
    }

    @Test
    func `A branch pin that moved revision reads as an update`() {
        let before = ResolvedPin(
            identity: "toba-ui", location: "u", branch: "main", revision: "aaaaaaaaaa")
        let after = ResolvedPin(
            identity: "toba-ui", location: "u", branch: "main", revision: "bbbbbbbbbb")
        let moves = PinMove.moves(from: ["toba-ui": before], to: ["toba-ui": after])

        #expect(moves.count == 1)
        #expect(moves[0].from == "branch main@aaaaaaa")
        #expect(moves[0].to == "branch main@bbbbbbb")
    }

    // MARK: - Reading the command's report

    @Test
    func `An update line with the name on both sides of the arrow reads one move`() {
        let report = """
            Computing the effect of updating the package dependencies...
            1 dependency has changed:
            ~ toba-data 3.12.4 -> toba-data 3.12.5
            """

        #expect(
            PinMove.planned(
                fromReport: report)
                == [.updated("toba-data", from: "3.12.4", to: "3.12.5")])
    }

    @Test
    func `An update line with the name on one side of the arrow reads one move`() {
        #expect(
            PinMove.planned(
                fromReport: "~ toba-core 1.4.0 -> 1.5.0")
                == [.updated("toba-core", from: "1.4.0", to: "1.5.0")])
    }

    @Test
    func `An update line to a multi-word state keeps every word`() {
        #expect(
            PinMove.planned(
                fromReport: "~ toba-ui 1.0.0 -> branch main")
                == [.updated("toba-ui", from: "1.0.0", to: "branch main")])
    }

    @Test
    func `An added line and a removed line read their states`() {
        let report = """
            2 dependencies have changed:
            + toba-hash 2.0.0
            - toba-xml 1.1.0
            """

        #expect(
            PinMove.planned(
                fromReport: report) == [
                    .added("toba-hash", to: "2.0.0"),
                    .removed("toba-xml", from: "1.1.0"),
                ])
    }

    @Test
    func `A report of no change reads no move`() {
        let report = """
            Fetching https://github.com/toba/toba-data
            Computing the effect of updating the package dependencies...
            0 dependencies have changed.
            """

        #expect(PinMove.planned(fromReport: report).isEmpty)
    }

    @Test
    func `A flag echoed into the output is not read as a removal`() {
        #expect(PinMove.planned(fromReport: "--dry-run\n-Xswiftc -Onone").isEmpty)
    }

    @Test
    func `An update line without an arrow is not read as a move`() {
        #expect(PinMove.planned(fromReport: "~ toba-data 3.12.4").isEmpty)
    }

    // MARK: - Rendering a block

    @Test
    func `A block of moves opens with the header`() {
        let lines = PinMove.lines(
            [.updated("toba-data", from: "3.12.4", to: "3.12.5")],
            header: "Pin changes:",
            whenEmpty: "No pin changed.",
        )

        #expect(lines == ["Pin changes:", "  ~ toba-data 3.12.4 → 3.12.5"])
    }

    @Test
    func `An empty block reads as the one empty line`() {
        #expect(
            PinMove.lines(
                [], header: "Pin changes:", whenEmpty: "No pin changed.")
                == ["No pin changed."])
    }
}
