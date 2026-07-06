import Testing
import Foundation
@testable import XCMCPTools

struct StoreKitLaunchAdvisoryTests {
    /// Builds a scheme with the given Run-action StoreKit `identifier` (or none), plus an unrelated
    /// Test-action reference to prove only the Run action drives the launch warning.
    private static func schemeXML(launchIdentifier: String?, testIdentifier: String?) -> String {
        func block(_ action: String, _ identifier: String?) -> String {
            guard let identifier else { return "   <\(action)>\n   </\(action)>" }
            return """
                   <\(action)>
                      <StoreKitConfigurationFileReference
                         identifier = "\(identifier)">
                      </StoreKitConfigurationFileReference>
                   </\(action)>
                """
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme version = "1.7">
            \(block("TestAction", testIdentifier))
            \(block("LaunchAction", launchIdentifier))
            </Scheme>

            """
    }

    /// Creates a temp `.xcodeproj` container holding `App.xcscheme`, and optionally a `.storekit`
    /// file at repo root so a `../../../Config.storekit` reference resolves.
    private static func makeFixture(
        launchIdentifier: String?,
        testIdentifier: String? = nil,
        writeStorekit: Bool = true,
    ) throws -> (project: String, base: String) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let schemesDir = base.appendingPathComponent("TestProject.xcodeproj/xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemesDir, withIntermediateDirectories: true)
        try schemeXML(launchIdentifier: launchIdentifier, testIdentifier: testIdentifier)
            .write(
                to: schemesDir.appendingPathComponent("App.xcscheme"),
                atomically: true, encoding: .utf8)

        if writeStorekit {
            try "{}".write(
                to: base.appendingPathComponent("Config.storekit"),
                atomically: true, encoding: .utf8)
        }
        return (base.appendingPathComponent("TestProject.xcodeproj").path, base.path)
    }

    @Test
    func `Run action StoreKit reference produces a warning`() throws {
        let fixture = try Self.makeFixture(launchIdentifier: "../../../Config.storekit")
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let warning = StoreKitLaunchAdvisory.warning(
            scheme: "App", projectPath: fixture.project, workspacePath: nil,
        )
        let message = try #require(warning)
        #expect(message.contains("StoreKit configuration not applied"))
        #expect(message.contains("../../../Config.storekit"))
        #expect(message.contains("SKTestSession"))
        // The reference resolves, so no "does not resolve" note.
        #expect(!message.contains("does not resolve"))
    }

    @Test
    func `No StoreKit reference yields no warning`() throws {
        let fixture = try Self.makeFixture(launchIdentifier: nil)
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let warning = StoreKitLaunchAdvisory.warning(
            scheme: "App", projectPath: fixture.project, workspacePath: nil,
        )
        #expect(warning == nil)
    }

    @Test
    func `Only a Test action reference does not warn on launch`() throws {
        let fixture = try Self.makeFixture(
            launchIdentifier: nil, testIdentifier: "../../../Config.storekit",
        )
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let warning = StoreKitLaunchAdvisory.warning(
            scheme: "App", projectPath: fixture.project, workspacePath: nil,
        )
        #expect(warning == nil, "Only the Run action reference should drive the launch warning")
    }

    @Test
    func `Unresolved reference is flagged in the warning`() throws {
        // ../../ is the wrong depth (points inside the .xcodeproj) — resolves to nothing.
        let fixture = try Self.makeFixture(
            launchIdentifier: "../../Config.storekit", writeStorekit: true,
        )
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        let warning = StoreKitLaunchAdvisory.warning(
            scheme: "App", projectPath: fixture.project, workspacePath: nil,
        )
        let message = try #require(warning)
        #expect(message.contains("does not resolve"))
    }

    @Test
    func `Nil or unknown scheme yields no warning`() throws {
        let fixture = try Self.makeFixture(launchIdentifier: "../../../Config.storekit")
        defer { try? FileManager.default.removeItem(atPath: fixture.base) }

        #expect(
            StoreKitLaunchAdvisory.warning(
                scheme: nil, projectPath: fixture.project, workspacePath: nil,
            ) == nil)
        #expect(
            StoreKitLaunchAdvisory.warning(
                scheme: "Missing", projectPath: fixture.project, workspacePath: nil,
            ) == nil)
    }
}
