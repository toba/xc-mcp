import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct NotarizeVerifyTests {
    @Test(arguments: [
        ("/tmp/App.app", SignedProductKind.app),
        ("/tmp/App.app/", SignedProductKind.app),
        ("/tmp/Installer.pkg", SignedProductKind.pkg),
        ("/tmp/Image.DMG", SignedProductKind.dmg),
    ])
    func `Product kind follows the path extension`(path: String, kind: SignedProductKind) {
        #expect(SignedProductKind(path: path) == kind)
    }

    @Test
    func `Unsupported extension has no product kind`() {
        #expect(SignedProductKind(path: "/tmp/tool") == nil)
        #expect(SignedProductKind(path: "/tmp/archive.zip") == nil)
    }

    @Test
    func `Gatekeeper check picks the assessment type for each kind`() {
        #expect(
            SignedProductKind.app.checks(path: "/p").last?
                .arguments == [
                    "--assess", "-vvv", "--type", "exec", "/p",
                ])
        #expect(
            SignedProductKind.pkg.checks(path: "/p").last?
                .arguments == [
                    "--assess", "-vvv", "--type", "install", "/p",
                ])
        #expect(
            SignedProductKind.dmg.checks(path: "/p").last?
                .arguments == [
                    "--assess", "-vvv", "--type", "open", "--context", "context:primary-signature",
                    "/p",
                ])
    }

    @Test
    func `Signature check uses codesign except for an installer package`() {
        let app = SignedProductKind.app.checks(path: "/p")
        #expect(app.map(\.executable) == ["codesign", "xcrun", "spctl"])
        #expect(app.first?.arguments == ["--verify", "--deep", "--strict", "--verbose=2", "/p"])
        #expect(app[1].arguments == ["stapler", "validate", "/p"])

        let pkg = SignedProductKind.pkg.checks(path: "/p")
        #expect(pkg.first?.executable == "pkgutil")
        #expect(pkg.first?.arguments == ["--check-signature", "/p"])
    }

    @Test
    func `Report flags a signed product that Gatekeeper rejects as not notarized`() {
        let checks = SignedProductKind.app.checks(path: "/p/App.app")
        let report = VerificationReport(
            path: "/p/App.app",
            outcomes: [
                .init(
                    check: checks[0],
                    result: .init(
                        exitCode: 0, stdout: "",
                        stderr:
                            "/p/App.app: valid on disk\n/p/App.app: satisfies its Designated Requirement",
                    )),
                .init(
                    check: checks[1],
                    result: .init(
                        exitCode: 65, stdout: "",
                        stderr: "App.app does not have a ticket stapled to it.",
                    )),
                .init(
                    check: checks[2],
                    result: .init(
                        exitCode: 3, stdout: "",
                        stderr:
                            "/p/App.app: rejected\nsource=Unnotarized Developer ID\norigin=Developer ID Application: Example (ABCDE12345)",
                    )),
            ])

        #expect(!report.passed)
        let text = report.text
        #expect(text.contains("FAIL"))
        #expect(text.contains("[PASS] Signature"))
        #expect(text.contains("[FAIL] Stapled ticket"))
        #expect(text.contains("[FAIL] Gatekeeper"))
        #expect(text.contains("Gatekeeper source: Unnotarized Developer ID"))
        #expect(text.contains("not notarized"))
    }

    @Test
    func `Report passes when every check passes`() {
        let checks = SignedProductKind.dmg.checks(path: "/p/App.dmg")
        let report = VerificationReport(
            path: "/p/App.dmg",
            outcomes: checks.map {
                .init(
                    check: $0,
                    result: .init(
                        exitCode: 0, stdout: "",
                        stderr: "/p/App.dmg: accepted\nsource=Notarized Developer ID",
                    ))
            })

        #expect(report.passed)
        #expect(report.text.contains("PASS"))
        #expect(!report.text.contains("[FAIL]"))
        #expect(report.text.contains("Gatekeeper source: Notarized Developer ID"))
        #expect(!report.text.contains("not notarized"))
    }

    @Test
    func `Verify rejects an unsupported product type`() async throws {
        let file = TemporaryDirectory.url.appendingPathComponent("tool")
        try Data().write(to: file)

        await #expect(throws: MCPError.self) {
            try await NotarizeTool().execute(arguments: [
                "action": .string("verify"), "path": .string(file.path),
            ])
        }
    }

    @Test
    func `Verify rejects a missing path`() async {
        let path = TemporaryDirectory.url.appendingPathComponent("Missing.app").path

        await #expect(throws: MCPError.self) {
            try await NotarizeTool().execute(arguments: [
                "action": .string("verify"), "path": .string(path),
            ])
        }
    }

    @Test
    func `Verify reports failed checks for an unsigned app without throwing`() async throws {
        let app = TemporaryDirectory.url.appendingPathComponent("Unsigned.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true,
        )

        let result = try await NotarizeTool().execute(arguments: [
            "action": .string("verify"), "path": .string(app.path),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("[FAIL] Signature"))
        #expect(text.contains("[FAIL] Stapled ticket"))
        #expect(text.contains("[FAIL] Gatekeeper"))
    }
}
