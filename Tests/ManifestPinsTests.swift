import Testing
import Foundation
@testable import XCMCPCore

@Suite("Manifest pins")
struct ManifestPinsTests {
    /// A manifest shaped like the ones in the workspace: one-line pins, a multi-line pin, a
    /// commented-out pin, a non-version requirement, and a local path dependency.
    static let manifest = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(
          name: "toba-data",
          dependencies: [
            // .package(url: "https://github.com/toba/toba-old", from: "9.9.9"),
            .package(url: "https://github.com/toba/toba-core", from: "1.13.0"),
            .package(url: "https://github.com/toba/toba-hash", from: "1.3.0"),
            .package(
              url: "https://github.com/toba/toba-macros",
              from: "1.2.0"
            ),
            .package(url: "https://github.com/apple/swift-syntax", exact: "601.0.1"),
          ],
        )
        """

    @Test func `reads every declared pin in source order`() {
        let pins = ManifestPins.parse(Self.manifest)
        #expect(pins.map(\.identity) == ["toba-core", "toba-hash", "toba-macros", "swift-syntax"])
    }

    @Test func `skips a pin inside a comment`() {
        #expect(!ManifestPins.parse(Self.manifest).contains { $0.identity == "toba-old" })
    }

    @Test func `reads a pin whose arguments span several lines`() {
        let pin = ManifestPins.parse(Self.manifest).first { $0.identity == "toba-macros" }
        #expect(pin?.version == SemanticVersion("1.2.0"))
    }

    @Test func `names the keyword of a requirement it cannot raise`() {
        let pin = ManifestPins.parse(Self.manifest).first { $0.identity == "swift-syntax" }
        #expect(pin?.requirement == .other("exact"))
        #expect(pin?.versionOffsets == nil)
    }

    /// Reads the fixture and rewrites it, the way a caller holding a parsed manifest does.
    static func rewriting(_ versions: [String: SemanticVersion]) -> ManifestPins.Rewrite {
        ManifestPins.rewrite(manifest, pins: ManifestPins.read(manifest).pins, to: versions)
    }

    @Test func `raises only the floors it is given`() {
        let rewrite = Self.rewriting([
            "toba-core": SemanticVersion("1.13.3")!, "toba-macros": SemanticVersion("1.4.0")!,
        ],)
        #expect(rewrite.changes.map(\.identity) == ["toba-core", "toba-macros"])
        #expect(rewrite.text.contains("toba-core\", from: \"1.13.3\""))
        #expect(rewrite.text.contains("from: \"1.4.0\""))
        #expect(rewrite.text.contains("toba-hash\", from: \"1.3.0\""))
    }

    @Test func `leaves a floor already at or above the wanted version alone`() {
        let rewrite = Self.rewriting(["toba-core": SemanticVersion("1.12.0")!])
        #expect(rewrite.changes.isEmpty)
        #expect(rewrite.text == Self.manifest)
    }

    @Test func `changes nothing else in the file`() {
        let rewrite = Self.rewriting(["toba-core": SemanticVersion("2.0.0")!])
        let before = Self.manifest.replacingOccurrences(of: "1.13.0", with: "2.0.0")
        #expect(rewrite.text == before)
    }

    @Test func `reads a local path dependency`() {
        let text = """
            dependencies: [
              .package(path: "../toba-core"),
              .package(url: "https://github.com/toba/toba-hash", from: "1.3.0"),
            ]
            """
        #expect(ManifestPins.localPaths(text) == ["../toba-core"])
    }

    @Test func `reports no local path dependency for a manifest that declares none`() {
        #expect(ManifestPins.localPaths(Self.manifest).isEmpty)
    }

    @Test func `one pass reads the same pins and paths as two`() {
        let text = """
            dependencies: [
              .package(path: "../toba-core"),
              .package(url: "https://github.com/toba/toba-hash", from: "1.3.0"),
            ]
            """
        let reading = ManifestPins.read(text)
        #expect(reading.pins == ManifestPins.parse(text))
        #expect(reading.localPaths == ManifestPins.localPaths(text))
    }

    @Test func `ignores a package call inside a block comment`() {
        let text = """
            /*
            .package(url: "https://github.com/toba/toba-core", from: "1.0.0"),
            */
            .package(url: "https://github.com/toba/toba-hash", from: "1.3.0"),
            """
        #expect(ManifestPins.parse(text).map(\.identity) == ["toba-hash"])
    }

    @Test func `reads a pin that names the package before the url`() {
        let text =
            #".package(name: "Core", url: "https://github.com/toba/toba-core", from: "1.2.0")"#
        let pins = ManifestPins.parse(text)
        #expect(pins.count == 1)
        #expect(pins[0].identity == "toba-core")
        #expect(pins[0].version == SemanticVersion("1.2.0"))
    }

    @Test func `reads a pin that states its requirement as a nested call`() {
        let text = """
            .package(
              url: "https://github.com/toba/toba-core",
              .upToNextMajor(from: "1.2.0")
            )
            """
        #expect(ManifestPins.parse(text).first?.version == SemanticVersion("1.2.0"))
    }

    @Test func `reads no pin from an empty manifest`() { #expect(ManifestPins.parse("").isEmpty) }
}
