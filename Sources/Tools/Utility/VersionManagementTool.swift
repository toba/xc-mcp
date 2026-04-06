import MCP
import System
import XCMCPCore
import Foundation
import Subprocess

/// Manages marketing version and build numbers using `agvtool`.
///
/// Wraps `xcrun agvtool` for reading and updating version strings in
/// Xcode projects. Useful for CI/CD version bumping before archive builds.
///
/// ## Example
///
/// ```
/// version_management(project_dir: "/path/to/project", action: "get")
/// version_management(project_dir: "/path/to/project", action: "set_marketing_version", version: "2.1.0")
/// version_management(project_dir: "/path/to/project", action: "bump_build")
/// ```
public struct VersionManagementTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "version_management",
            description:
            "Manage marketing version and build numbers in an Xcode project using agvtool. Supports reading current versions, setting new versions, and incrementing build numbers. The project must use CURRENT_PROJECT_VERSION and MARKETING_VERSION build settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_dir": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the directory containing the .xcodeproj. Required.",
                        ),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("get"),
                            .string("set_marketing_version"),
                            .string("set_build_number"),
                            .string("bump_build"),
                        ]),
                        "description": .string(
                            "Action to perform: 'get' reads both versions, 'set_marketing_version' sets the marketing version, 'set_build_number' sets the build number, 'bump_build' increments the build number.",
                        ),
                    ]),
                    "version": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The version string to set. Required for set_marketing_version and set_build_number actions.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_dir"), .string("action")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let projectDir = try arguments.getRequiredString("project_dir")
        let action = try arguments.getRequiredString("action")

        switch action {
            case "get":
                return try await getVersions(projectDir: projectDir)
            case "set_marketing_version":
                let version = try arguments.getRequiredString("version")
                return try await setMarketingVersion(projectDir: projectDir, version: version)
            case "set_build_number":
                let version = try arguments.getRequiredString("version")
                return try await setBuildNumber(projectDir: projectDir, version: version)
            case "bump_build":
                return try await bumpBuildNumber(projectDir: projectDir)
            default:
                throw MCPError.invalidParams(
                    "Unknown action '\(action)'. Use get, set_marketing_version, set_build_number, or bump_build.",
                )
        }
    }

    private func getVersions(projectDir: String) async throws -> CallTool.Result {
        let dir = FilePath(projectDir)

        async let marketingResult = ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["agvtool", "what-marketing-version", "-terse1"],
            workingDirectory: dir,
            timeout: .seconds(15),
        )
        async let buildResult = ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["agvtool", "what-version", "-terse"],
            workingDirectory: dir,
            timeout: .seconds(15),
        )

        let marketing = try await marketingResult
        let build = try await buildResult

        let marketingVersion = marketing.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildNumber = build.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var output = "Marketing version: \(marketingVersion.isEmpty ? "(not set)" : marketingVersion)\n"
        output += "Build number: \(buildNumber.isEmpty ? "(not set)" : buildNumber)"

        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }

    private func setMarketingVersion(
        projectDir: String,
        version: String,
    ) async throws -> CallTool.Result {
        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["agvtool", "new-marketing-version", version],
            workingDirectory: FilePath(projectDir),
            timeout: .seconds(15),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "agvtool failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result(content: [.text(
            text: "Marketing version set to \(version)\n\(result.stdout)",
            annotations: nil,
            _meta: nil,
        )])
    }

    private func setBuildNumber(
        projectDir: String,
        version: String,
    ) async throws -> CallTool.Result {
        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["agvtool", "new-version", "-all", version],
            workingDirectory: FilePath(projectDir),
            timeout: .seconds(15),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "agvtool failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result(content: [.text(
            text: "Build number set to \(version)\n\(result.stdout)",
            annotations: nil,
            _meta: nil,
        )])
    }

    private func bumpBuildNumber(projectDir: String) async throws -> CallTool.Result {
        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: ["agvtool", "next-version", "-all"],
            workingDirectory: FilePath(projectDir),
            timeout: .seconds(15),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "agvtool failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result(content: [.text(
            text: result.stdout,
            annotations: nil,
            _meta: nil,
        )])
    }
}
