import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SwiftPackageDocsToolTests {
    let sessionManager = SessionManager()

    // MARK: - Catalog discovery and target mapping

    @Test
    func `A catalog under an explicit target path maps to that target`() {
        let targets = [
            SwiftPackageDocsTool.PackageTarget(
                name: "TobaMathView", path: "Sources", type: "regular"),
            SwiftPackageDocsTool.PackageTarget(
                name: "TobaMathViewTests", path: "Tests", type: "test"),
        ]
        let catalogs = SwiftPackageDocsTool.matchCatalogs(
            ["/pkg/Sources/Documentation.docc"], toTargets: targets, packagePath: "/pkg",
        )

        #expect(catalogs.count == 1)
        #expect(catalogs[0].moduleName == "TobaMathView")
        #expect(catalogs[0].displayName == "TobaMathView")
    }

    @Test
    func `A catalog under the conventional layout maps to the target named by its directory`() {
        let targets = [
            SwiftPackageDocsTool.PackageTarget(name: "Widget", path: nil, type: "regular"),
            SwiftPackageDocsTool.PackageTarget(name: "Gadget", path: nil, type: "regular"),
        ]
        let catalogs = SwiftPackageDocsTool.matchCatalogs(
            ["/pkg/Sources/Gadget/Gadget.docc"], toTargets: targets, packagePath: "/pkg",
        )

        #expect(catalogs[0].moduleName == "Gadget")
    }

    @Test
    func `A catalog outside every target has no module and falls back to its own name`() {
        let targets = [
            SwiftPackageDocsTool.PackageTarget(name: "Widget", path: nil, type: "regular")
        ]
        let catalogs = SwiftPackageDocsTool.matchCatalogs(
            ["/pkg/Guides.docc"], toTargets: targets, packagePath: "/pkg",
        )

        #expect(catalogs[0].moduleName == nil)
        #expect(catalogs[0].displayName == "Guides")
    }

    @Test
    func `A target name that is not a C99 identifier becomes an underscored module name`() {
        #expect(SwiftPackageDocsTool.moduleName(forTarget: "toba-math-view") == "toba_math_view")
        #expect(SwiftPackageDocsTool.moduleName(forTarget: "Widget") == "Widget")
    }

    @Test
    func `Catalog discovery finds the catalog and skips the build directory`() throws {
        let root = TemporaryDirectory.url
        let manager = FileManager.default

        let catalog = root.appendingPathComponent("Sources/Widget/Widget.docc")
        let buildCatalog = root.appendingPathComponent(".build/checkouts/Other/Other.docc")
        try manager.createDirectory(at: catalog, withIntermediateDirectories: true)
        try manager.createDirectory(at: buildCatalog, withIntermediateDirectories: true)

        let found = SwiftPackageDocsTool.findCatalogs(in: root.path)

        #expect(found.count == 1)
        #expect(found[0].hasSuffix("Sources/Widget/Widget.docc"))
    }

    // MARK: - Symbol graph selection

    @Test
    func `The symbol graph directory comes from the last line of the SwiftPM log`() {
        let output = """
            Building for debugging...
            -- Emitting symbol graph for Widget
            Files written to /pkg/.build/arm64-apple-macosx/symbolgraph
            """

        #expect(
            SwiftPackageDocsTool.symbolGraphDirectory(
                fromOutput: output)
                == "/pkg/.build/arm64-apple-macosx/symbolgraph",
        )
    }

    @Test
    func `Only the module's own symbol graph files are selected`() {
        let names = [
            "Widget.symbols.json",
            "Widget@Swift.symbols.json",
            "WidgetHelper.symbols.json",
            "pkgPackageTests.symbols.json",
        ]

        let selected = SwiftPackageDocsTool.symbolGraphFiles(in: names, module: "Widget")

        #expect(selected.sorted() == ["Widget.symbols.json", "Widget@Swift.symbols.json"])
    }

    // MARK: - Diagnostics parsing

    @Test
    func `The DocC diagnostics file parses into diagnostics with a location and a fix-it`() throws {
        let json = """
            {
              "version": {"major": 1, "minor": 0, "patch": 0},
              "diagnostics": [
                {
                  "severity": "warning",
                  "summary": "'missing' doesn't exist at '/Widget'",
                  "notes": [],
                  "source": "file:///pkg/Sources/Widget/Widget.docc/Widget.md",
                  "range": {"start": {"line": 7, "column": 5}, "end": {"line": 7, "column": 20}},
                  "solutions": [{"summary": "Replace 'missing' with 'spin()'", "replacements": []}]
                }
              ]
            }
            """
        let diagnostics = try DocCDiagnosticParser.parse(diagnosticsFile: Data(json.utf8))

        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == "warning")
        #expect(diagnostics[0].sourcePath == "/pkg/Sources/Widget/Widget.docc/Widget.md")
        #expect(diagnostics[0].line == 7)
        #expect(diagnostics[0].column == 5)
        #expect(diagnostics[0].solutions == ["Replace 'missing' with 'spin()'"])
        #expect(diagnostics[0].isUnresolvedReference)
    }

    @Test
    func `Console output parses when no diagnostics file is written`() {
        let output = """
            /pkg/Sources/Widget/Widget.docc/Widget.md:7:5: warning: 'missing' doesn't exist at '/Widget'
            /pkg/Sources/Widget/Widget.swift:3:1: error: Parameter 'value' not found
            Compilation finished
            """

        let diagnostics = DocCDiagnosticParser.parseConsole(output)

        #expect(diagnostics.count == 2)
        #expect(diagnostics[0].line == 7)
        #expect(diagnostics[0].column == 5)
        #expect(diagnostics[0].isUnresolvedReference)
        #expect(diagnostics[1].severity == "error")
        #expect(!diagnostics[1].isUnresolvedReference)
    }

    @Test
    func `Console diagnostics parse from a CRLF log`() {
        let lines = [
            "/pkg/Sources/Widget/Widget.docc/Widget.md:7:5: warning: 'missing' doesn't exist",
            "/pkg/Sources/Widget/Widget.swift:3:1: error: Parameter 'value' not found",
        ]

        let fromLF = DocCDiagnosticParser.parseConsole(lines.joined(separator: "\n"))
        let fromCRLF = DocCDiagnosticParser.parseConsole(lines.joined(separator: "\r\n"))

        #expect(fromCRLF.count == 2)
        #expect(fromCRLF.map(\.severity) == fromLF.map(\.severity))
        #expect(fromCRLF.map(\.summary) == fromLF.map(\.summary))
        #expect(fromCRLF.map(\.line) == fromLF.map(\.line))
        #expect(fromCRLF[1].summary == "Parameter 'value' not found")
    }

    // MARK: - Formatting

    @Test
    func `Diagnostics group by file and the file with unresolved references comes first`() {
        let diagnostics = [
            DocCDiagnostic(
                severity: "warning",
                summary: "Parameter 'value' is missing documentation",
                sourcePath: "/pkg/Sources/Widget/Widget.swift",
                line: 3,
                column: 1,
            ),
            DocCDiagnostic(
                severity: "warning",
                summary: "'missing' doesn't exist at '/Widget'",
                sourcePath: "/pkg/Sources/Widget/Widget.docc/Guide.md",
                line: 9,
                column: 4,
                solutions: ["Replace 'missing' with 'spin()'"],
            ),
        ]

        let report = DocCDiagnosticFormatter.format(diagnostics, relativeTo: "/pkg")
        let sections = report.components(separatedBy: "\n\n")

        #expect(sections.count == 2)
        #expect(sections[0].hasPrefix("### Sources/Widget/Widget.docc/Guide.md"))
        #expect(sections[0].contains("- 9:4 warning: 'missing' doesn't exist at '/Widget'"))
        #expect(sections[0].contains("  - fix: Replace 'missing' with 'spin()'"))
        #expect(sections[1].hasPrefix("### Sources/Widget/Widget.swift"))
    }

    @Test
    func `The summary counts each severity and the unresolved references`() {
        let diagnostics = [
            DocCDiagnostic(severity: "warning", summary: "'a' doesn't exist at '/Widget'"),
            DocCDiagnostic(severity: "warning", summary: "'b' doesn't exist at '/Widget'"),
            DocCDiagnostic(severity: "error", summary: "Topic reference is malformed"),
        ]

        let summary = DocCDiagnosticFormatter.summary(diagnostics)

        #expect(summary == "1 error, 2 warnings (2 unresolved references)")
        #expect(DocCDiagnosticFormatter.summary([]) == "No diagnostics")
    }

    // MARK: - Argument validation

    @Test
    func `An unknown access level is rejected`() async throws {
        let tool = SwiftPackageDocsTool(sessionManager: sessionManager)

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "package_path": .string("/nonexistent"),
                "minimum_access_level": .string("secret"),
            ])
        }
    }

    // MARK: - End to end

    @Test(.timeLimit(.minutes(5)))
    func `Building a fixture catalog reports the unresolved links at each access level`()
        async throws
    {
        let package = try FixturePackage()

        let tool = SwiftPackageDocsTool(sessionManager: sessionManager)

        // A public symbol graph cannot see `polish()`, so the article link to it stays unresolved.
        let publicResult = try await tool.execute(arguments: ["package_path": .string(package.path)]
        )
        let publicReport = textContent(publicResult)
        #expect(publicReport.contains("Widget.md"))
        #expect(publicReport.contains("missingMethod"))
        #expect(publicReport.contains("polish"))
        #expect(publicReport.contains("unresolved reference"))

        // An internal symbol graph documents `polish()`, so only the invented symbol stays
        // unresolved. The archive path names directories that do not exist yet, because docc
        // refuses to run when the parent of its output path is missing.
        let archivePath = package.root.appendingPathComponent("out/nested/Widget.doccarchive").path
        let internalResult = try await tool.execute(arguments: [
            "package_path": .string(package.path),
            "minimum_access_level": .string("internal"),
            "render": .bool(true),
            "output_path": .string(archivePath),
        ])
        let internalReport = textContent(internalResult)
        #expect(internalReport.contains("missingMethod"))
        #expect(!internalReport.contains("polish"))
        #expect(internalReport.contains("Archive: \(archivePath)"))
        #expect(FileManager.default.fileExists(atPath: archivePath + "/index.html"))
    }

    // MARK: - Helpers

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined(separator: "\n")
    }
}

/// A throwaway Swift package with one target and one documentation catalog.
///
/// The catalog links one symbol that exists, one internal symbol, and one symbol that does not
/// exist, so a build reports a different set of unresolved links per access level.
///
/// The package is written into ``TemporaryDirectory/url``, so the calling suite needs the
/// `.temporaryDirectory` trait.
private struct FixturePackage {
    let root: URL

    var path: String { root.appendingPathComponent("DocsFixture").path }

    init() throws {
        root = TemporaryDirectory.url
        let packageRoot = root.appendingPathComponent("DocsFixture")
        let sources = packageRoot.appendingPathComponent("Sources/Widget")
        let catalog = sources.appendingPathComponent("Widget.docc")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

        try Self.manifest.write(
            to: packageRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8,
        )
        try Self.source.write(
            to: sources.appendingPathComponent("Widget.swift"),
            atomically: true,
            encoding: .utf8,
        )
        try Self.article.write(
            to: catalog.appendingPathComponent("Widget.md"),
            atomically: true,
            encoding: .utf8,
        )
    }

    private static let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "DocsFixture",
            targets: [.target(name: "Widget")]
        )
        """

    private static let source = """
        /// A widget.
        public struct Widget {
            /// Creates a widget.
            public init() {}

            /// Spins the widget.
            public func spin() {}

            /// Polishes the widget.
            func polish() {}
        }
        """

    private static let article = """
        # ``Widget``

        A fixture catalog.

        ## Overview

        Call ``Widget/spin()`` to spin it.
        Call ``Widget/polish()`` to polish it.
        Call ``Widget/missingMethod()`` to prove the link check works.
        """
}
