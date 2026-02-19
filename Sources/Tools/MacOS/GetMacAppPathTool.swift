import Foundation
import MCP
import XCMCPCore

public struct GetMacAppPathTool: Sendable {
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
            name: "get_mac_app_path",
            description:
                "Get the path to a built macOS app. Can find the app by bundle ID in Applications, or by build settings for the current project.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier to search for in /Applications and ~/Applications."
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Used to find the built app from build settings."
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Used to find the built app from build settings."
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to get the app path for. Uses session default if not specified."
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
        let bundleId = arguments.getString("bundle_id")

        // If bundle_id is provided, search for the app in Applications directories
        if let bundleId {
            if let appPath = findAppByBundleId(bundleId) {
                return CallTool.Result(
                    content: [
                        .text("App path for '\(bundleId)':\n\(appPath)")
                    ]
                )
            }
            throw MCPError.internalError(
                "Could not find app with bundle identifier '\(bundleId)' in Applications directories."
            )
        }

        // Otherwise, use build settings to find the app
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
                "scheme is required when using build settings. Set it with set_session_defaults or pass it directly."
            )
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
                "Either bundle_id, project_path, or workspace_path is required."
            )
        }

        do {
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings. Make sure the project has been built."
                )
            }

            // Verify the app exists
            if !FileManager.default.fileExists(atPath: appPath) {
                throw MCPError.internalError(
                    "App not found at expected path: \(appPath). Build the project first with build_macos."
                )
            }

            return CallTool.Result(
                content: [
                    .text("App path for scheme '\(scheme)':\n\(appPath)")
                ]
            )
        } catch {
            throw error.asMCPError()
        }
    }

    private func findAppByBundleId(_ bundleId: String) -> String? {
        let searchPaths = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        for searchPath in searchPaths {
            if let appPath = searchForApp(in: searchPath, bundleId: bundleId) {
                return appPath
            }
        }

        return nil
    }

    private func searchForApp(in directory: String, bundleId: String) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        for item in contents {
            let fullPath = "\(directory)/\(item)"
            if item.hasSuffix(".app") {
                if let appBundleId = getBundleIdentifier(forApp: fullPath), appBundleId == bundleId
                {
                    return fullPath
                }
            }
        }

        return nil
    }

    private func getBundleIdentifier(forApp appPath: String) -> String? {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let plistData = FileManager.default.contents(atPath: plistPath),
            let plist = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil) as? [String: Any],
            let bundleId = plist["CFBundleIdentifier"] as? String
        else {
            return nil
        }
        return bundleId
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        BuildSettingExtractor.extractAppPath(from: buildSettings)
    }
}
