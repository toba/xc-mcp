import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

/// Integration tests for discovery tools against real open-source repos.
/// Exercises both XcodeProj-based discovery and xcodebuild metadata queries.
/// Requires `scripts/fetch-fixtures.sh` to have been run first.
@Suite(.enabled(if: IntegrationFixtures.available))
struct DiscoveryIntegrationTests {
    private let sessionManager = SessionManager()
    private let xcodebuildRunner = XcodebuildRunner()

    // MARK: - discover_projects (XcodeProj-based, no xcodebuild)

    @Test func discoverProjects_IceCubesApp() throws {
        let tool = DiscoverProjectsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false,
            ),
        )
        let result = try tool.execute(arguments: [
            "path": .string(IntegrationFixtures.iceCubesRepoDir),
        ])

        let content = textContent(result)
        #expect(content.contains("IceCubesApp.xcodeproj"))
    }

    @Test func discoverProjects_Alamofire() throws {
        let tool = DiscoverProjectsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false,
            ),
        )
        let result = try tool.execute(arguments: [
            "path": .string(IntegrationFixtures.alamofireRepoDir),
        ])

        let content = textContent(result)
        #expect(content.contains("Alamofire.xcodeproj"))
    }

    @Test func discoverProjects_SwiftFormat() throws {
        let tool = DiscoverProjectsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.swiftFormatRepoDir, sandboxEnabled: false,
            ),
        )
        let result = try tool.execute(arguments: [
            "path": .string(IntegrationFixtures.swiftFormatRepoDir),
        ])

        let content = textContent(result)
        #expect(content.contains("SwiftFormat.xcodeproj"))
    }

    // MARK: - list_schemes (xcodebuild -list)

    @Test(.timeLimit(.minutes(2)))
    func listSchemes_IceCubesApp() async throws {
        let tool = ListSchemesTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
        ])

        let content = textContent(result)
        #expect(content.contains("IceCubesApp"))
    }

    @Test(.timeLimit(.minutes(2)))
    func listSchemes_Alamofire() async throws {
        let tool = ListSchemesTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
        ])

        let content = textContent(result)
        #expect(content.contains("Alamofire"))
    }

    // MARK: - show_build_settings (xcodebuild -showBuildSettings)

    @Test(.timeLimit(.minutes(2)))
    func showBuildSettings_Alamofire() async throws {
        let tool = ShowBuildSettingsTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "scheme": .string("Alamofire macOS"),
        ])

        let content = textContent(result)
        #expect(content.contains("PRODUCT_NAME"))
        #expect(content.contains("PRODUCT_BUNDLE_IDENTIFIER"))
    }

    @Test(.timeLimit(.minutes(2)))
    func showBuildSettings_withFilter() async throws {
        let tool = ShowBuildSettingsTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "scheme": .string("Alamofire macOS"),
            "filter": .string("PRODUCT_NAME"),
        ])

        let content = textContent(result)
        #expect(content.contains("PRODUCT_NAME"))
        // Filter should reduce output — bundle identifier shouldn't appear
        // unless it happens to contain "PRODUCT_NAME"
    }

    // MARK: - get_app_bundle_id

    @Test(.timeLimit(.minutes(2)))
    func getAppBundleId_IceCubesApp() async throws {
        let tool = GetAppBundleIdTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
            "scheme": .string("IceCubesApp"),
        ])

        let content = textContent(result)
        #expect(content.contains("IceCubesApp"))
    }

    // MARK: - get_mac_bundle_id

    @Test(.timeLimit(.minutes(2)))
    func getMacBundleId_Alamofire() async throws {
        let tool = GetMacBundleIdTool(
            xcodebuildRunner: xcodebuildRunner,
            sessionManager: sessionManager,
        )
        let result = try await tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "scheme": .string("Alamofire macOS"),
        ])

        let content = textContent(result)
        // Should contain a bundle identifier
        #expect(content.contains("org.alamofire.Alamofire") || content.contains("Bundle"))
    }

    // MARK: - Helpers

    private func textContent(_ result: CallTool.Result) -> String {
        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }
}
