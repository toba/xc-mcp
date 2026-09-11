import Testing
import Foundation
@testable import XCMCPCore

@Suite
struct SourcePackagesCacheTests {
    private static let cache = SourcePackagesCache(
        directory: "/Caches/xc-mcp/DerivedData/Jig-abc123-macosx/SourcePackages")

    // MARK: - Matching a package to its directories

    @Test
    func `A mirror name is the identity followed by a hash`() {
        let names = ["toba-data-8f2c1d", "toba-core-11aa22", "toba-data"]

        #expect(
            SourcePackagesCache.mirrorNames(
                in: names, identity: "toba-data")
                == ["toba-data-8f2c1d"])
    }

    @Test
    func `A mirror of a longer package name is not claimed by a shorter identity`() {
        // The remainder after the identity has to read as one hash, otherwise toba-data would take
        // the mirror of toba-data-manager.
        let names = ["toba-data-manager-8f2c1d"]

        #expect(SourcePackagesCache.mirrorNames(in: names, identity: "toba-data").isEmpty)
        #expect(
            SourcePackagesCache.mirrorNames(
                in: names, identity: "toba-data-manager")
                == names)
    }

    @Test
    func `A hash of letters and digits alike counts as one hash`() {
        let names = ["toba-data-9034845721", "toba-core-a1b2c3z9"]

        #expect(
            SourcePackagesCache.mirrorNames(
                in: names, identity: "toba-data")
                == ["toba-data-9034845721"])
        #expect(
            SourcePackagesCache.mirrorNames(
                in: names, identity: "toba-core")
                == ["toba-core-a1b2c3z9"])
    }

    @Test
    func `A mirror name matches whatever case the repository URL carries`() {
        #expect(
            SourcePackagesCache.mirrorNames(
                in: ["Toba-Data-8F2C1D"], identity: "toba-data")
                == ["Toba-Data-8F2C1D"])
    }

    @Test
    func `A working copy carries the bare name`() {
        let names = ["toba-data", "toba-core", "toba-data-8f2c1d"]

        #expect(
            SourcePackagesCache.checkoutNames(
                in: names, identity: "toba-data")
                == ["toba-data"])
    }

    // MARK: - Naming the caches

    @Test
    func `The notes name all three caches for one package`() {
        let notes = Self.cache.pathNotes(for: "toba-data")

        #expect(notes.count == 3)
        #expect(notes[0].contains("SourcePackages/checkouts/toba-data"))
        #expect(notes[1].contains("SourcePackages/repositories/toba-data-<hash>"))
        #expect(notes[2].contains("org.swift.swiftpm/repositories/toba-data-<hash>"))
    }

    @Test
    func `A failed checkout earns advice naming the caches and the tree`() {
        let output = """
            error: Could not resolve package dependencies:
              Couldn't check out revision '0b5f4c9'
            """
        let advice = Self.cache.revisionAdvice(for: output, identity: "toba-data")

        #expect(advice?.contains("predates the pinned commit") == true)
        #expect(advice?.contains(Self.cache.directory) == true)
        #expect(advice?.contains("org.swift.swiftpm/repositories/toba-data-<hash>") == true)
    }

    @Test
    func `An unrelated failure earns no cache advice`() {
        #expect(
            Self.cache.revisionAdvice(
                for: "error: no such module 'Foo'", identity: "toba-data") == nil)
    }

    // MARK: - Locating the tree

    @Test
    func `The tree sits inside the scoped DerivedData root`() {
        let cache = SourcePackagesCache.locate(
            workspacePath: nil,
            projectPath: "/repo/Jig.xcodeproj",
            destination: "platform=macOS",
            environment: [:],
        )

        #expect(cache?.directory.hasSuffix("/SourcePackages") == true)
        #expect(cache?.checkouts.hasSuffix("/SourcePackages/checkouts") == true)
        #expect(cache?.repositories.hasSuffix("/SourcePackages/repositories") == true)
    }

    @Test
    func `An overridden DerivedData path holds the tree`() {
        let cache = SourcePackagesCache.locate(
            workspacePath: nil,
            projectPath: "/repo/Jig.xcodeproj",
            destination: "platform=macOS",
            environment: ["XC_MCP_DERIVED_DATA_PATH": "/tmp/dd"],
        )

        #expect(cache?.directory == "/tmp/dd/SourcePackages")
    }

    @Test
    func `A refresh of a tree that holds nothing reports nothing`() async {
        // Both parents are absent, so the refresh finds no mirror to fetch and runs no subprocess.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("xc-mcp-no-such-tree-\(UUID().uuidString)").path
        let empty = SourcePackagesCache(directory: missing, sharedRepositories: missing + "/shared")

        #expect(await empty.refresh(identities: ["toba-data"]).isEmpty)
    }

    @Test
    func `Clearing a tree removes the directory`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("xc-mcp-tree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("checkouts/toba-data"),
            withIntermediateDirectories: true,
        )
        let cache = SourcePackagesCache(directory: directory.path)

        #expect(cache.exists)
        #expect(cache.clear())
        #expect(!cache.exists)
    }
}
