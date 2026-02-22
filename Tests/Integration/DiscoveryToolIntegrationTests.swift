import MCP
import Testing
import XCMCPCore
import Foundation
@testable import XCMCPTools

/// Integration tests for project discovery against real open-source repos.
/// Requires `scripts/fetch-fixtures.sh` to have been run first.
@Suite(.enabled(if: IntegrationFixtures.available))
struct DiscoveryToolIntegrationTests {
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

    // MARK: - Helpers

    private func textContent(_ result: CallTool.Result) -> String {
        guard case let .text(content) = result.content.first else {
            Issue.record("Expected text content")
            return ""
        }
        return content
    }
}
