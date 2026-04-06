import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Validates asset catalogs (.xcassets) for issues using `actool`.
///
/// Wraps `xcrun actool` in validation mode to check for missing sizes,
/// incorrect formats, and other configuration problems before they cause
/// build failures.
///
/// ## Example
///
/// ```
/// validate_asset_catalog(path: "/path/to/Assets.xcassets")
/// validate_asset_catalog(path: "/path/to/Assets.xcassets", platform: "iphoneos")
/// ```
public struct ValidateAssetCatalogTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "validate_asset_catalog",
            description:
            "Validate an asset catalog (.xcassets) for missing sizes, incorrect formats, and configuration issues. Runs actool in validation mode to catch problems before they cause build failures.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcassets directory to validate.",
                        ),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("macosx"), .string("iphoneos"),
                            .string("iphonesimulator"), .string("appletvos"),
                            .string("watchos"), .string("xros"),
                        ]),
                        "description": .string(
                            "Target platform for validation. Default: macosx.",
                        ),
                    ]),
                    "minimum_deployment_target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Minimum deployment target version (e.g., '15.0'). Default: platform-appropriate.",
                        ),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let path = try arguments.getRequiredString("path")
        let platform = arguments.getString("platform") ?? "macosx"
        let deploymentTarget = arguments.getString("minimum_deployment_target") ?? "15.0"

        guard FileManager.default.fileExists(atPath: path) else {
            throw MCPError.invalidParams("Asset catalog not found at '\(path)'")
        }

        let args = [
            "actool",
            "--warnings",
            "--errors",
            "--notices",
            "--output-format", "human-readable-text",
            "--platform", platform,
            "--minimum-deployment-target", deploymentTarget,
            path,
        ]

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(args),
            mergeStderr: false,
            timeout: .seconds(60),
        )

        // actool writes warnings/errors to stderr and may exit non-zero for warnings
        let warnings = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        var message = ""
        if !warnings.isEmpty {
            message += "## Warnings/Errors\n\n\(warnings)\n"
        }
        if !output.isEmpty {
            if !message.isEmpty { message += "\n" }
            message += output
        }
        if message.isEmpty {
            message = "Asset catalog validation passed with no issues."
        }

        return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
    }
}
