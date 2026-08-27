import Testing
import Foundation
@testable import XCMCPCore

@Suite(.temporaryDirectory)
struct IndexStoreLocatorTests {
    /// Creates a store directory under the temporary package root and puts one unit file in it.
    @discardableResult
    private func makeStore(_ relativePath: String) throws -> String {
        let directory = TemporaryDirectory.url.appendingPathComponent(relativePath)
        let units = directory.appendingPathComponent("v5/units")
        try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)
        try Data().write(to: units.appendingPathComponent("Example.o-ABCDEF"))
        return directory.path
    }

    // MARK: - Layouts

    @Test
    func `Finds the swift-build store at .build/out`() throws {
        let expected = try makeStore(".build/out")

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(location.path == expected)
        #expect(location.exists)
    }

    @Test
    func `Finds the native build system store at .build/debug/index/store`() throws {
        let expected = try makeStore(".build/debug/index/store")

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(location.path == expected)
        #expect(location.exists)
    }

    @Test
    func `Prefers the swift-build store when both layouts exist`() throws {
        let expected = try makeStore(".build/out")
        try makeStore(".build/debug/index/store")

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(location.path == expected)
    }

    @Test
    func `Finds the release store when the caller asks for it`() throws {
        let expected = try makeStore(".build/release/index/store")

        let location = IndexStoreLocator.locate(
            packagePath: TemporaryDirectory.path, configuration: "release",
        )

        #expect(location.path == expected)
        #expect(location.exists)
    }

    // MARK: - Fallback

    @Test
    func `Falls back to the native build system path when no store exists`() {
        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(location.path == TemporaryDirectory.path + "/.build/debug/index/store")
        #expect(!location.exists)
    }

    @Test
    func `A store directory without records does not count`() throws {
        let directory = TemporaryDirectory.url.appendingPathComponent(".build/out")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(!location.exists)
    }

    @Test
    func `An empty units directory does not count`() throws {
        let units = TemporaryDirectory.url.appendingPathComponent(".build/out/v5/units")
        try FileManager.default.createDirectory(at: units, withIntermediateDirectories: true)

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(!location.exists)
    }

    @Test
    func `A file named v5 does not count as records`() throws {
        let directory = TemporaryDirectory.url.appendingPathComponent(".build/out")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("v5"))

        #expect(!IndexStoreLocator.locate(packagePath: TemporaryDirectory.path).exists)
    }

    @Test
    func `Follows a symlinked store`() throws {
        let target = try makeStore(".build/out")
        let index = TemporaryDirectory.url.appendingPathComponent(".build/debug/index")
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: index.appendingPathComponent("store"),
            withDestinationURL: URL(fileURLWithPath: target),
        )

        let location = IndexStoreLocator.locate(packagePath: TemporaryDirectory.path)

        #expect(location.exists)
    }

    // MARK: - Candidates

    @Test
    func `Candidates list both layouts, swift-build first`() {
        let candidates = IndexStoreLocator.candidates(packagePath: "/tmp/pkg")

        #expect(candidates == ["/tmp/pkg/.build/out", "/tmp/pkg/.build/debug/index/store"])
    }

    @Test
    func `Expands a tilde in the package path`() {
        let candidates = IndexStoreLocator.candidates(packagePath: "~/pkg")

        #expect(candidates.allSatisfy { !$0.hasPrefix("~") })
    }
}
