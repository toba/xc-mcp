import Testing
import Foundation
@testable import XCMCPCore

struct SemanticVersionTests {
    @Test func `parses a three-component version`() {
        let version = SemanticVersion("2.1.0")
        #expect(version?.major == 2)
        #expect(version?.minor == 1)
        #expect(version?.patch == 0)
        #expect(version?.isPrerelease == false)
    }

    @Test func `parses a short version by padding with zeros`() {
        #expect(SemanticVersion("2")?.description == "2.0.0")
        #expect(SemanticVersion("2.1")?.description == "2.1.0")
    }

    @Test func `strips a leading v`() { #expect(SemanticVersion("v3.4.5")?.description == "3.4.5") }

    @Test func `parses prerelease and build metadata`() {
        let version = SemanticVersion("1.0.0-beta.2+sha.abc")
        #expect(version?.prerelease == ["beta", "2"])
        #expect(version?.build == "sha.abc")
        #expect(version?.isPrerelease == true)
    }

    @Test func `rejects text that is not a version`() {
        #expect(SemanticVersion("release") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
        #expect(SemanticVersion("") == nil)
    }

    @Test func `orders by major then minor then patch`() {
        #expect(SemanticVersion("1.0.0")! < SemanticVersion("2.0.0")!)
        #expect(SemanticVersion("2.1.0")! < SemanticVersion("2.2.0")!)
        #expect(SemanticVersion("2.1.0")! < SemanticVersion("2.1.1")!)
    }

    @Test func `orders a prerelease below its release`() {
        #expect(SemanticVersion("2.0.0-beta.1")! < SemanticVersion("2.0.0")!)
        #expect(SemanticVersion("2.0.0-alpha")! < SemanticVersion("2.0.0-beta")!)
        #expect(SemanticVersion("2.0.0-beta.1")! < SemanticVersion("2.0.0-beta.2")!)
        #expect(SemanticVersion("2.0.0-1")! < SemanticVersion("2.0.0-alpha")!)
    }

    @Test func `ignores build metadata when comparing`() {
        #expect(SemanticVersion("1.0.0+a") == SemanticVersion("1.0.0+b"))
    }

    @Test func `reports the next major and minor bounds`() {
        let version = SemanticVersion("2.1.3")!
        #expect(version.nextMajor.description == "3.0.0")
        #expect(version.nextMinor.description == "2.2.0")
    }
}
