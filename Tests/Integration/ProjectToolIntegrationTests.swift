import Foundation
import MCP
import Testing
import XCMCPCore

@testable import XCMCPTools

/// Integration tests that exercise project tools against real open-source repos.
/// Requires `scripts/fetch-fixtures.sh` to have been run first.
@Suite(.enabled(if: IntegrationFixtures.available))
struct ProjectToolIntegrationTests {

    // MARK: - list_targets

    @Test func listTargets_IceCubesApp() throws {
        let tool = ListTargetsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath)
        ])

        let content = textContent(result)
        #expect(content.contains("IceCubesApp"))
        #expect(content.contains("IceCubesShareExtension"))
    }

    @Test func listTargets_Alamofire() throws {
        let tool = ListTargetsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath)
        ])

        let content = textContent(result)
        #expect(content.contains("Alamofire"))
    }

    @Test func listTargets_SwiftFormat() throws {
        let tool = ListTargetsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.swiftFormatRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.swiftFormatProjectPath)
        ])

        let content = textContent(result)
        #expect(content.contains("SwiftFormat"))
    }

    // MARK: - list_files

    @Test func listFiles_IceCubesApp() throws {
        let tool = ListFilesTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath),
            "target_name": .string("IceCubesApp"),
        ])

        let content = textContent(result)
        // IceCubesApp main target references frameworks/assets; Swift code is in local packages
        #expect(content.contains("Files in target 'IceCubesApp'"))
    }

    @Test func listFiles_Alamofire() throws {
        let tool = ListFilesTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "target_name": .string("Alamofire iOS"),
        ])

        let content = textContent(result)
        #expect(content.contains(".swift"))
    }

    // MARK: - list_groups

    @Test func listGroups_IceCubesApp() throws {
        let tool = ListGroupsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath)
        ])

        let content = textContent(result)
        // Should have a non-trivial group hierarchy
        #expect(content.contains("IceCubesApp"))
    }

    @Test func listGroups_Alamofire() throws {
        let tool = ListGroupsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath)
        ])

        let content = textContent(result)
        // Alamofire groups use directory names like "Source", "Documentation", etc.
        #expect(content.contains("Source"))
    }

    // MARK: - list_build_configurations

    @Test func listBuildConfigurations_IceCubesApp() throws {
        let tool = ListBuildConfigurationsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath)
        ])

        let content = textContent(result)
        #expect(content.contains("Debug"))
        #expect(content.contains("Release"))
    }

    @Test func listBuildConfigurations_Alamofire() throws {
        let tool = ListBuildConfigurationsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath)
        ])

        let content = textContent(result)
        #expect(content.contains("Debug"))
        #expect(content.contains("Release"))
    }

    // MARK: - get_build_settings

    @Test func getBuildSettings_Alamofire() throws {
        let tool = GetBuildSettingsTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.alamofireRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.alamofireProjectPath),
            "target_name": .string("Alamofire iOS"),
        ])

        let content = textContent(result)
        // Verify we get build settings back (key = value format)
        #expect(content.contains("Build settings for target"))
    }

    // MARK: - list_swift_packages

    @Test func listSwiftPackages_IceCubesApp() throws {
        let tool = ListSwiftPackagesTool(
            pathUtility: PathUtility(
                basePath: IntegrationFixtures.iceCubesRepoDir, sandboxEnabled: false))
        let result = try tool.execute(arguments: [
            "project_path": .string(IntegrationFixtures.iceCubesProjectPath)
        ])

        let content = textContent(result)
        // IceCubesApp has local packages in Packages/
        #expect(content.contains("Package") || content.contains("local"))
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
