import Testing
import Foundation
@testable import XCMCPCore

@Suite(.temporaryDirectory)
struct PackageModuleLocatorTests {
    /// Creates a directory under the temporary package root and puts one module file in it.
    @discardableResult
    private func makeModuleDirectory(
        _ relativePath: String,
        modificationDate: Date? = nil,
    ) throws -> String {
        let fm = FileManager.default
        let directory = TemporaryDirectory.url.appendingPathComponent(relativePath)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("Example.swiftmodule"))
        if let modificationDate {
            try fm.setAttributes(
                [.modificationDate: modificationDate], ofItemAtPath: directory.path)
        }
        return directory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Layouts

    @Test
    func `Finds the native build system Modules directory`() throws {
        let expected = try makeModuleDirectory(".build/arm64-apple-macosx/debug/Modules")

        let paths = PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path)

        #expect(paths == [expected])
    }

    @Test
    func `Finds the swift-build products directory through the configuration symlink`() throws {
        let expected = try makeModuleDirectory(".build/out/Products/Debug")
        try FileManager.default.createSymbolicLink(
            at: TemporaryDirectory.url.appendingPathComponent(".build/debug"),
            withDestinationURL: URL(fileURLWithPath: expected),
        )

        let paths = PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path)

        #expect(paths == [expected])
    }

    @Test
    func `Finds a release configuration directory`() throws {
        let expected = try makeModuleDirectory(".build/release")

        let paths = PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path)

        #expect(paths == [expected])
    }

    // MARK: - Ordering

    @Test
    func `Orders the newest directory first`() throws {
        let older = try makeModuleDirectory(
            ".build/arm64-apple-macosx/debug/Modules",
            modificationDate: Date(timeIntervalSince1970: 1_000),
        )
        let newer = try makeModuleDirectory(
            ".build/debug", modificationDate: Date(timeIntervalSince1970: 2_000),
        )

        let paths = PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path)

        #expect(paths == [newer, older])
    }

    // MARK: - Exclusions

    @Test
    func `Ignores a directory holding no module`() throws {
        try FileManager.default.createDirectory(
            at: TemporaryDirectory.url.appendingPathComponent(".build/debug"),
            withIntermediateDirectories: true,
        )

        #expect(PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path).isEmpty)
    }

    @Test
    func `Ignores the index build output`() throws {
        try makeModuleDirectory(".build/index-build/arm64-apple-macosx/debug/Modules")
        try makeModuleDirectory(".build/index-build/debug")

        #expect(PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path).isEmpty)
    }

    @Test
    func `Ignores the checkouts directory`() throws {
        try makeModuleDirectory(".build/checkouts/debug")

        #expect(PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path).isEmpty)
    }

    @Test
    func `Reports nothing for a package that never built`() {
        #expect(PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path).isEmpty)
    }

    @Test
    func `Reports nothing for a directory that does not exist`() {
        let missing = TemporaryDirectory.url.appendingPathComponent("absent").path

        #expect(PackageModuleLocator.searchPaths(packagePath: missing).isEmpty)
    }

    // MARK: - Deduplication

    @Test
    func `Reports one path when two candidates resolve to the same directory`() throws {
        let expected = try makeModuleDirectory(".build/debug")
        try FileManager.default.createSymbolicLink(
            at: TemporaryDirectory.url.appendingPathComponent(".build/link"),
            withDestinationURL: TemporaryDirectory.url.appendingPathComponent(".build"),
        )

        let paths = PackageModuleLocator.searchPaths(packagePath: TemporaryDirectory.path)

        #expect(paths == [expected])
    }
}
