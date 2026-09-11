import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite
struct SwiftPackageUpdateToolTests {
    private static func pin(_ identity: String, _ version: String) -> ResolvedPin {
        .init(identity: identity, location: "https://github.com/toba/\(identity)", version: version)
    }

    private static let pins = [
        "toba-core": Self.pin("toba-core", "1.4.0"),
        "toba-data": Self.pin("toba-data", "3.12.4"),
    ]

    // MARK: - Naming a dependency

    @Test
    func `A name no pin carries is refused and the known identities are named`() throws {
        let error = #expect(throws: MCPError.self) {
            try SwiftPackageUpdateTool.validate("toba-dat", against: Self.pins, at: "/repo")
        }
        let message = try #require(error).localizedDescription

        #expect(message.contains("toba-core, toba-data"))
        #expect(message.contains("/repo/Package.resolved"))
    }

    @Test
    func `A name a pin carries passes, whatever its case`() throws {
        try SwiftPackageUpdateTool.validate("toba-data", against: Self.pins, at: "/repo")
        try SwiftPackageUpdateTool.validate("Toba-Data", against: Self.pins, at: "/repo")
    }

    @Test
    func `A package with no pins yet accepts any name`() throws {
        try SwiftPackageUpdateTool.validate("toba-data", against: [:], at: "/repo")
    }

    // MARK: - The write report

    @Test
    func `A write report names each pin that moved`() {
        let report = SwiftPackageUpdateTool.writeReport(
            [.updated("toba-data", from: "3.12.4", to: "3.12.5")],
            packageName: "toba-data",
            packagePath: "/repo",
            elapsed: "3.1s",
        )

        #expect(report.contains("Updated toba-data at /repo (3.1s)"))
        #expect(report.contains("  ~ toba-data 3.12.4 → 3.12.5"))
        #expect(!report.contains("from: floor"))
    }

    @Test
    func `A write report that moved nothing points at the requirement floor`() {
        let report = SwiftPackageUpdateTool.writeReport(
            [], packageName: "toba-data", packagePath: "/repo", elapsed: "1.0s",
        )

        #expect(report.contains("No pin moved."))
        #expect(report.contains("from: floor"))
        #expect(report.contains("toba-data"))
    }

    @Test
    func `A write report over every dependency says so`() {
        let report = SwiftPackageUpdateTool.writeReport(
            [], packageName: nil, packagePath: "/repo", elapsed: "1.0s",
        )

        #expect(report.contains("Updated every dependency"))
        #expect(report.contains("Every requirement already admits"))
    }

    // MARK: - The dry-run report

    @Test
    func `A dry run report says nothing was written and how to write it`() {
        let report = SwiftPackageUpdateTool.dryRunReport(
            [.updated("toba-data", from: "3.12.4", to: "3.12.5")],
            packageName: "toba-data",
            packagePath: "/repo",
            elapsed: "2.0s",
        )

        #expect(report.contains("Package.resolved was not written"))
        #expect(report.contains("Planned pin changes:"))
        #expect(report.contains("  ~ toba-data 3.12.4 → 3.12.5"))
        #expect(report.contains("dry_run: false"))
    }

    @Test
    func `A dry run with nothing to move offers no way to write it`() {
        let report = SwiftPackageUpdateTool.dryRunReport(
            [], packageName: nil, packagePath: "/repo", elapsed: "2.0s",
        )

        #expect(report.contains("No pin would move."))
        #expect(!report.contains("dry_run: false"))
    }

    // MARK: - The declared tool

    @Test
    func `The tool declares package name, dry run and the session package path`() {
        let tool = SwiftPackageUpdateTool(sessionManager: SessionManager(enableWarmup: false))
            .tool()

        #expect(tool.name == "swift_package_update")

        guard case let .object(schema) = tool.inputSchema,
              case let .object(properties) = schema["properties"]
        else {
            Issue.record("swift_package_update declares no object schema")
            return
        }

        #expect(properties["package_name"] != nil)
        #expect(properties["dry_run"] != nil)
        #expect(properties["package_path"] != nil)
        #expect(properties["timeout"] != nil)
        #expect(tool.annotations.readOnlyHint == false)
    }
}
