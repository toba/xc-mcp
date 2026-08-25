import MCP
import XCMCPCore
import Foundation

public struct GetMacAppPathTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "get_mac_app_path",
            description:
                "Get the path to a built macOS app. Can find the app by bundle ID in Applications, or by build settings for the current project.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier to search for in /Applications and ~/Applications.",
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Used to find the built app from build settings.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Used to find the built app from build settings.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to get the app path for. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let bundleID = arguments.getString("bundle_id")

        // If bundle_id is provided, search for the app in Applications directories
        if let bundleID {
            if let appPath = findAppByBundleID(bundleID) {
                return CallTool.Result.text("App path for '\(bundleID)':\n\(appPath)")
            }
            throw MCPError.internalError(
                "Could not find app with bundle identifier '\(bundleID)' in Applications directories.",
            )
        }

        // Otherwise, use build settings to find the app. Both messages name bundle_id, which the
        // shared resolvers know nothing about, so restate them here.
        let projectPath: String?
        let workspacePath: String?

        do {
            (
                projectPath, workspacePath
            ) = try await sessionManager.resolveBuildPaths(from: arguments)
        } catch {
            throw MCPError.invalidParams(
                "Either bundle_id, project_path, or workspace_path is required.",
            )
        }

        let scheme: String

        do {
            scheme = try await sessionManager.resolveScheme(from: arguments)
        } catch {
            throw MCPError.invalidParams(
                "scheme is required when using build settings. Set it with set_session_defaults or pass it directly.",
            )
        }

        // Get configuration (nil = honor the scheme's own configuration)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        do {
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: XcodebuildRunner.macOSDestination,
            )

            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings. Make sure the project has been built.",
                )
            }

            // Verify the app exists
            if !FileManager.default.fileExists(atPath: appPath) {
                throw MCPError.internalError(
                    "App not found at expected path: \(appPath). Build the project first with build_macos.",
                )
            }

            return CallTool.Result.text("App path for scheme '\(scheme)':\n\(appPath)")
        } catch {
            throw try error.asMCPError()
        }
    }

    private func findAppByBundleID(_ bundleID: String) -> String? {
        let searchPaths = ["/Applications", NSHomeDirectory() + "/Applications"]

        for searchPath in searchPaths {
            if let appPath = searchForApp(in: searchPath, bundleID: bundleID) { return appPath }
        }

        return nil
    }

    private func searchForApp(in directory: String, bundleID: String) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return nil
        }

        for item in contents {
            let fullPath = "\(directory)/\(item)"

            if item.hasSuffix(".app") {
                if let appBundleID = getBundleIdentifier(forApp: fullPath),
                   appBundleID == bundleID { return fullPath }
            }
        }

        return nil
    }

    private func getBundleIdentifier(forApp appPath: String) -> String? {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let plistData = FileManager.default.contents(atPath: plistPath),
            let plist = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil,
            ) as? [String: Any],
            let bundleID = plist["CFBundleIdentifier"] as? String else { return nil }
        return bundleID
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        BuildSettingExtractor.extractAppPath(from: buildSettings)
    }
}
