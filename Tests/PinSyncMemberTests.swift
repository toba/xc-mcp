import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite("Pin sync member", .temporaryDirectory)
struct PinSyncMemberTests {
    static let rootManifest = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(
          name: "toba-data",
          dependencies: [
            .package(url: "https://github.com/toba/toba-core", from: "1.13.0"),
          ],
        )
        """

    static let benchmarkManifest = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(
          name: "Benchmarks",
          dependencies: [
            .package(url: "https://github.com/toba/toba-benchmark", from: "1.0.0"),
          ],
        )
        """

    /// Creates a package directory holding a root manifest and, when asked, a nested suite.
    static func makePackage(
        named name: String,
        nested: Bool = false,
        buildDirectory: Bool = false,
    ) throws -> String {
        let root = TemporaryDirectory.path + "/" + name
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: root, withIntermediateDirectories: true)
        try rootManifest.write(toFile: root + "/Package.swift", atomically: true, encoding: .utf8)

        if nested {
            try fileManager.createDirectory(
                atPath: root + "/Benchmarks", withIntermediateDirectories: true,
            )
            try benchmarkManifest.write(
                toFile: root + "/Benchmarks/Package.swift", atomically: true, encoding: .utf8,
            )
        }

        if buildDirectory {
            try fileManager.createDirectory(
                atPath: root + "/.build/checkouts/toba-core", withIntermediateDirectories: true,
            )
            try rootManifest.write(
                toFile: root + "/.build/Package.swift", atomically: true, encoding: .utf8,
            )
        }
        return root
    }

    @Test func `loads a package member from its root manifest`() throws {
        let member = try PinSyncMember.load(root: try Self.makePackage(named: "toba-data"))
        #expect(member.kind == .package)
        #expect(member.identity == "toba-data")
        #expect(member.manifests.map(\.relativePath) == ["Package.swift"])
        #expect(member.pinnedIdentities == ["toba-core"])
    }

    @Test func `reads a nested benchmark manifest as well as the root one`() throws {
        let member = try PinSyncMember.load(
            root: try Self.makePackage(named: "toba-data", nested: true),
        )
        #expect(
            member.manifests.map(\.relativePath) == ["Package.swift", "Benchmarks/Package.swift"])
        #expect(member.pinnedIdentities == ["toba-core", "toba-benchmark"])
    }

    @Test func `never descends into a hidden build directory`() throws {
        let member = try PinSyncMember.load(
            root: try Self.makePackage(named: "toba-data", buildDirectory: true),
        )
        #expect(member.manifests.map(\.relativePath) == ["Package.swift"])
    }

    @Test func `refuses a path that is not a directory`() {
        #expect(throws: MCPError.self) {
            try PinSyncMember.load(root: TemporaryDirectory.path + "/absent")
        }
    }

    @Test func `refuses a directory with no manifest and no project`() throws {
        let root = TemporaryDirectory.path + "/empty"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        #expect(throws: MCPError.self) { try PinSyncMember.load(root: root) }
    }

    @Test func `names the pins file that sits beside a manifest`() {
        #expect(PinSyncEngine.resolvedPath(besides: "Package.swift") == "Package.resolved")
        #expect(
            PinSyncEngine.resolvedPath(
                besides: "Benchmarks/Package.swift")
                == "Benchmarks/Package.resolved",
        )
    }
}
