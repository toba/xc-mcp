import Foundation
import MCP
import XCMCPCore

public struct GetAppBundleIdTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "get_app_bundle_id",
            description:
                "Get the bundle identifier for an iOS/tvOS/watchOS app target from build settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified."),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to get the bundle ID for. Uses session default if not specified."
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get project/workspace path
        let projectPath: String?
        if case let .string(value) = arguments["project_path"] {
            projectPath = value
        } else {
            projectPath = await sessionManager.projectPath
        }

        let workspacePath: String?
        if case let .string(value) = arguments["workspace_path"] {
            workspacePath = value
        } else {
            workspacePath = await sessionManager.workspacePath
        }

        // Get scheme
        let scheme: String
        if case let .string(value) = arguments["scheme"] {
            scheme = value
        } else if let sessionScheme = await sessionManager.scheme {
            scheme = sessionScheme
        } else {
            throw MCPError.invalidParams(
                "scheme is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get configuration
        let configuration: String
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else if let sessionConfig = await sessionManager.configuration {
            configuration = sessionConfig
        } else {
            configuration = "Debug"
        }

        // Validate we have either project or workspace
        if projectPath == nil && workspacePath == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

        do {
            let result = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            if result.succeeded {
                guard let bundleId = extractBundleId(from: result.stdout) else {
                    throw MCPError.internalError(
                        "Could not find PRODUCT_BUNDLE_IDENTIFIER in build settings for scheme '\(scheme)'"
                    )
                }

                var output = "Bundle identifier for scheme '\(scheme)' (\(configuration)):\n"
                output += bundleId

                // Also extract product name if available
                if let productName = extractProductName(from: result.stdout) {
                    output += "\n\nProduct name: \(productName)"
                }

                return CallTool.Result(content: [.text(output)])
            } else {
                throw MCPError.internalError(
                    "Failed to get build settings: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func extractBundleId(from buildSettings: String) -> String? {
        // Try JSON parsing first
        if let data = buildSettings.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            for targetSettings in parsed {
                if let settings = targetSettings["buildSettings"] as? [String: Any],
                    let bundleId = settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String
                {
                    // Skip variables that haven't been resolved
                    if !bundleId.contains("$(") {
                        return bundleId
                    }
                }
            }
        }

        // Fallback to line parsing
        let lines = buildSettings.components(separatedBy: .newlines)
        for line in lines where line.contains("PRODUCT_BUNDLE_IDENTIFIER") {
            if let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER") {
                let afterKey = String(line[range.upperBound...])
                let cleaned = afterKey.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: " = ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && !cleaned.hasPrefix("$") {
                    return cleaned
                }
            }
        }

        return nil
    }

    private func extractProductName(from buildSettings: String) -> String? {
        // Try JSON parsing first
        if let data = buildSettings.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            for targetSettings in parsed {
                if let settings = targetSettings["buildSettings"] as? [String: Any],
                    let productName = settings["PRODUCT_NAME"] as? String
                {
                    if !productName.contains("$(") {
                        return productName
                    }
                }
            }
        }

        return nil
    }
}
