import MCP
import Testing
import Foundation
import XCMCPTools
@testable import XCMCPCore

/// End-to-end cover for a release build of a package whose tests use `@testable`.
///
/// SwiftPM passes `-enable-testing` to a debug build alone, so this shape used to fail with "module
/// 'Widget' was not compiled for testing" and the only workaround was an `unsafeFlags` edit to
/// `Package.swift`. Both halves run here: the raw argument list still fails, and the tool succeeds.
@Suite struct ReleaseTestabilityIntegrationTests {
    /// Writes a package with one internal symbol a test reaches through `@testable`.
    ///
    /// - Returns: The package directory, which the caller removes.
    private func makePackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("testability-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/Widget")
        let tests = root.appendingPathComponent("Tests/WidgetTests")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "Widget",
            targets: [
                .target(name: "Widget"),
                .testTarget(name: "WidgetTests", dependencies: ["Widget"]),
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8,
        )

        // `internal` is the access level that needs -enable-testing to cross into the test target.
        try "struct Widget { static let secret = 7 }\n".write(
            to: sources.appendingPathComponent("Widget.swift"),
            atomically: true,
            encoding: .utf8,
        )

        try """
        import XCTest
        @testable import Widget

        final class WidgetTests: XCTestCase {
            func testSecret() { XCTAssertEqual(Widget.secret, 7) }
        }
        """.write(
            to: tests.appendingPathComponent("WidgetTests.swift"),
            atomically: true,
            encoding: .utf8,
        )

        return root
    }

    // Two real release builds run here. The limit bounds a wedged `swift build` so it cannot hang
    // the whole suite.
    @Test(.timeLimit(.minutes(5)))
    func `a release build of the test targets needs -enable-testing and the tool passes it`()
        async throws
    {
        let package = try makePackage()
        defer { try? FileManager.default.removeItem(at: package) }

        let runner = SwiftRunner()

        // Without the flag the compiler refuses the @testable import. This is the failure the
        // manifest edit used to work around.
        let bare = try await runner.run(
            arguments: ["build", "-c", "release", "--build-tests"],
            workingDirectory: package.path,
            timeout: .seconds(300),
        )
        #expect(!bare.succeeded)
        #expect(bare.output.contains("was not compiled for testing"))

        let tool = SwiftPackageBuildTool(swiftRunner: runner, sessionManager: SessionManager())
        let result = try await tool.execute(arguments: [
            "package_path": .string(package.path),
            "configuration": .string("release"),
            "build_tests": .bool(true),
            "timeout": .int(600),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("expected a text result, got \(result.content)")
            return
        }
        #expect(message.contains("Build succeeded"))
        #expect(message.contains("release configuration"))
    }
}
