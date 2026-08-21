import Testing
import Foundation
@testable import XCMCPCore

struct ResolvedPinStateTests {
    @Test func `a version pin reads as the bare version`() {
        let pin = ResolvedPin(
            identity: "toba-web", location: "https://github.com/toba/toba-web",
            version: "2.1.0", revision: "abcdef1234",
        )
        #expect(pin.stateDescription == "2.1.0")
    }

    @Test func `a branch pin names the branch and the short revision`() {
        let pin = ResolvedPin(
            identity: "toba-web", location: "https://github.com/toba/toba-web",
            branch: "main", revision: "abcdef1234",
        )
        #expect(pin.stateDescription == "branch main@abcdef1")
    }

    @Test func `a branch pin with no revision marks the revision unknown`() {
        let pin = ResolvedPin(
            identity: "toba-web", location: "https://github.com/toba/toba-web", branch: "main",
        )
        #expect(pin.stateDescription == "branch main@?")
    }

    @Test func `a revision-only pin reads as the short revision`() {
        let pin = ResolvedPin(
            identity: "toba-web", location: "https://github.com/toba/toba-web",
            revision: "abcdef1234",
        )
        #expect(pin.stateDescription == "revision abcdef1")
    }

    @Test func `an empty pin reads as unresolved`() {
        let pin = ResolvedPin(identity: "toba-web", location: "https://github.com/toba/toba-web")
        #expect(pin.stateDescription == "(unresolved)")
    }
}
