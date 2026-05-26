import Testing
import Foundation
@testable import XCMCPCore

struct InteractSettleTests {
    private func element(
        id: Int,
        role: String,
        title: String? = nil,
        value: String? = nil,
        enabled: Bool = true,
        focused: Bool = false,
        depth: Int = 0,
        childCount: Int = 0,
    ) -> InteractElement {
        InteractElement(
            id: id,
            role: role,
            subrole: nil,
            title: title,
            value: value,
            identifier: nil,
            roleDescription: nil,
            position: nil,
            size: nil,
            enabled: enabled,
            focused: focused,
            actions: [],
            depth: depth,
            childCount: childCount,
        )
    }

    @Test func `identical trees produce identical fingerprints`() {
        let a = [
            element(id: 0, role: "AXWindow", title: "Main", childCount: 1),
            element(id: 1, role: "AXButton", title: "OK", depth: 1),
        ]
        let b = [
            element(id: 0, role: "AXWindow", title: "Main", childCount: 1),
            element(id: 1, role: "AXButton", title: "OK", depth: 1),
        ]
        #expect(InteractRunner.fingerprint(a) == InteractRunner.fingerprint(b))
    }

    @Test func `changed value yields a different fingerprint`() {
        let before = [element(id: 0, role: "AXTextField", value: "")]
        let after = [element(id: 0, role: "AXTextField", value: "hello")]
        #expect(InteractRunner.fingerprint(before) != InteractRunner.fingerprint(after))
    }

    @Test func `focus and enabled changes are reflected`() {
        let before = [element(id: 0, role: "AXButton", title: "Go", enabled: false)]
        let after = [element(id: 0, role: "AXButton", title: "Go", enabled: true, focused: true)]
        #expect(InteractRunner.fingerprint(before) != InteractRunner.fingerprint(after))
    }

    @Test func `added child changes the fingerprint`() {
        let before = [element(id: 0, role: "AXList", childCount: 0)]
        let after = [
            element(id: 0, role: "AXList", childCount: 1),
            element(id: 1, role: "AXCell", title: "Row", depth: 1),
        ]
        #expect(InteractRunner.fingerprint(before) != InteractRunner.fingerprint(after))
    }

    @Test func `fingerprint is order sensitive`() {
        let forward = [
            element(id: 0, role: "AXButton", title: "A"),
            element(id: 1, role: "AXButton", title: "B"),
        ]
        let reversed = [
            element(id: 0, role: "AXButton", title: "B"),
            element(id: 1, role: "AXButton", title: "A"),
        ]
        #expect(InteractRunner.fingerprint(forward) != InteractRunner.fingerprint(reversed))
    }
}
