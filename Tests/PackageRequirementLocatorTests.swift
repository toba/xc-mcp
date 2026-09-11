import PathKit
import Testing
import XcodeProj
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct PackageRequirementLocatorTests {
    /// Writes a project holding one remote reference and one local package reference.
    ///
    /// - Parameters:
    ///   - directory: The directory that receives `Locator.xcodeproj`.
    ///   - remote: The repository URL and requirement of the remote reference, if any.
    ///   - localPath: The relative path of the local package reference, if any.
    /// - Returns: The path of the written project.
    private static func project(
        in directory: URL,
        remote: (url: String, requirement: XCRemoteSwiftPackageReference.VersionRequirement)? = nil,
        localPath: String? = nil,
    ) throws -> String {
        let path = Path(directory.path) + "Locator.xcodeproj"
        try TestProjectHelper.createTestProject(name: "Locator", at: path)

        let xcodeproj = try XcodeProj(path: path)
        let root = try #require(try xcodeproj.pbxproj.rootProject())

        if let remote {
            let reference = XCRemoteSwiftPackageReference(
                repositoryURL: remote.url, versionRequirement: remote.requirement,
            )
            xcodeproj.pbxproj.add(object: reference)
            root.remotePackages.append(reference)
        }

        if let localPath {
            let reference = XCLocalSwiftPackageReference(relativePath: localPath)
            xcodeproj.pbxproj.add(object: reference)
            root.localPackages.append(reference)
        }
        try xcodeproj.write(path: path)
        return path.string
    }

    private static func writeManifest(_ text: String, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(
            to: directory.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8,
        )
    }

    @Test
    func `A project reference reports its own file and admits the pinned version`() throws {
        let temporary = TemporaryDirectory.url
        let path = try Self.project(
            in: temporary,
            remote: ("https://github.com/toba/toba-core", .upToNextMajorVersion("1.4.0")),
        )

        let search = PackageRequirementLocator.search(for: "toba-core", pinned: "1.4.3", in: path)

        #expect(search.unreadable.isEmpty)
        let found = try #require(search.requirement)
        #expect(found.requirement == "from: 1.4.0")
        #expect(found.file == path)
        #expect(found.source == .project)
        #expect(found.admission == .admits)
    }

    @Test
    func `A pin below the declared floor is excluded`() throws {
        let temporary = TemporaryDirectory.url
        let path = try Self.project(
            in: temporary,
            remote: ("https://github.com/toba/toba-core", .upToNextMajorVersion("1.4.0")),
        )

        let found = try #require(
            PackageRequirementLocator.search(for: "toba-core", pinned: "1.3.9", in: path)
                .requirement)

        #expect(found.admission == .excludes)
    }

    @Test
    func `A local package manifest reports the manifest path`() throws {
        let temporary = TemporaryDirectory.url
        let packageRoot = temporary.appendingPathComponent("Root")
        let projectDirectory = packageRoot.appendingPathComponent("Xcode")
        try FileManager.default.createDirectory(
            at: projectDirectory, withIntermediateDirectories: true,
        )
        try Self.writeManifest(
            """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "Root",
                dependencies: [
                    .package(url: "https://github.com/toba/toba-diagnostics", from: "1.2.0"),
                ],
            )
            """,
            in: packageRoot,
        )
        let path = try Self.project(in: projectDirectory, localPath: "..")

        let search = PackageRequirementLocator.search(
            for: "toba-diagnostics", pinned: "1.2.1", in: path,
        )

        #expect(search.unreadable.isEmpty)
        let found = try #require(search.requirement)
        #expect(found.requirement == "from: 1.2.0")
        #expect(found.file == packageRoot.appendingPathComponent("Package.swift").path)
        #expect(found.source == .manifest)
        #expect(found.admission == .admits)
    }

    @Test
    func `A manifest reached by path declares the requirement`() throws {
        let temporary = TemporaryDirectory.url
        let packageRoot = temporary.appendingPathComponent("Root")
        let nested = temporary.appendingPathComponent("Nested")
        try Self.writeManifest(
            """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "Root",
                dependencies: [.package(path: "../Nested")],
            )
            """,
            in: packageRoot,
        )
        try Self.writeManifest(
            """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "Nested",
                dependencies: [
                    .package(url: "https://github.com/toba/toba-hash", from: "2.0.0"),
                ],
            )
            """,
            in: nested,
        )
        let path = try Self.project(in: temporary, localPath: "Root")

        let found = try #require(
            PackageRequirementLocator.search(for: "toba-hash", pinned: "2.1.0", in: path)
                .requirement)

        #expect(found.file == nested.appendingPathComponent("Package.swift").path)
        #expect(found.source == .manifest)
    }

    @Test
    func `A requirement form with no comparable window reports unknown`() throws {
        let temporary = TemporaryDirectory.url
        let packageRoot = temporary.appendingPathComponent("Root")
        try Self.writeManifest(
            """
            // swift-tools-version: 6.3
            import PackageDescription

            let package = Package(
                name: "Root",
                dependencies: [
                    .package(url: "https://github.com/toba/toba-xml", branch: "main"),
                ],
            )
            """,
            in: packageRoot,
        )
        let path = try Self.project(in: temporary, localPath: "Root")

        let found = try #require(
            PackageRequirementLocator.search(for: "toba-xml", pinned: nil, in: path).requirement)

        #expect(found.requirement.contains("branch"))
        #expect(found.admission == .unknown)
    }

    @Test
    func `A package nothing in reach declares is not found`() throws {
        let temporary = TemporaryDirectory.url
        let path = try Self.project(
            in: temporary,
            remote: ("https://github.com/toba/toba-core", .upToNextMajorVersion("1.4.0")),
        )

        let search = PackageRequirementLocator.search(
            for: "toba-markdown", pinned: "1.0.0", in: path,
        )

        #expect(search.requirement == nil)
        #expect(search.unreadable.isEmpty)
    }

    @Test
    func `A project the reader refuses is reported rather than passed over`() {
        let path = TemporaryDirectory.url.appendingPathComponent("Missing.xcodeproj").path

        let search = PackageRequirementLocator.search(for: "toba-core", pinned: "1.0.0", in: path)

        #expect(search.requirement == nil)
        #expect(search.unreadable.map(\.file) == [path])
    }

    @Test
    func `A container that is neither a project nor a workspace is reported`() {
        let path = TemporaryDirectory.url.appendingPathComponent("Package.swift").path

        let search = PackageRequirementLocator.search(for: "toba-core", pinned: "1.0.0", in: path)

        #expect(search.requirement == nil)
        #expect(search.unreadable.map(\.file) == [path])
    }
}
