import MCP
import XCMCPCore
import Foundation

public struct GetMacBundleIDTool: Sendable {
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
            name: "get_mac_bundle_id",
            description:
                "Get the bundle identifier for a macOS app. Can read from a .app bundle directly or from build settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a .app bundle. If provided, reads the bundle ID directly from Info.plist.",
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to get the bundle ID for. Uses session default if not specified.",
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
        // If app_path is provided, read directly from the app bundle
        if let appPath = arguments.getString("app_path") {
            return try readBundleIDFromApp(appPath: appPath)
        }

        // Otherwise, use build settings. Both messages name app_path, which the shared resolvers
        // know nothing about, so restate them here.
        let projectPath: String?
        let workspacePath: String?

        do {
            (
                projectPath, workspacePath
            ) = try await sessionManager.resolveBuildPaths(from: arguments)
        } catch {
            throw MCPError.invalidParams(
                "Either app_path, project_path, or workspace_path is required.",
            )
        }

        let scheme: String

        do {
            scheme = try await sessionManager.resolveScheme(from: arguments)
        } catch {
            throw MCPError.invalidParams(
                "scheme is required when not providing app_path. Set it with set_session_defaults or pass it directly.",
            )
        }

        // Get configuration (nil = honor the scheme's own configuration)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        do {
            let result = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            if result.succeeded {
                let settings = BuildSettingSet(result.stdout)

                guard let bundleID = settings.bundleID else {
                    throw MCPError.internalError(
                        "Could not find PRODUCT_BUNDLE_IDENTIFIER in build settings for scheme '\(scheme)'",
                    )
                }

                var output = "Bundle identifier for macOS scheme '\(scheme)' "
                    + "(\(configuration ?? "scheme default")):\n"
                output += bundleID

                // Also extract product name if available
                if let productName = settings.productName {
                    output += "\n\nProduct name: \(productName)"
                }

                return CallTool.Result.text(output)
            } else {
                throw MCPError.internalError("Failed to get build settings: \(result.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    private func readBundleIDFromApp(appPath: String) throws -> CallTool.Result {
        let plistPath = "\(appPath)/Contents/Info.plist"

        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw MCPError.invalidParams(
                "App bundle not found or invalid: \(appPath). Info.plist not found.",
            )
        }

        guard let plistData = FileManager.default.contents(atPath: plistPath),
            let plist = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil,
            ) as? [String: Any]
        else {
            throw MCPError.internalError("Failed to read Info.plist from \(appPath)")
        }

        guard let bundleID = plist["CFBundleIdentifier"] as? String else {
            throw MCPError.internalError(
                "CFBundleIdentifier not found in Info.plist for \(appPath)",
            )
        }

        var output = "Bundle identifier for '\(appPath)':\n"
        output += bundleID

        // Also extract other useful info
        if let bundleName = plist["CFBundleName"] as? String {
            output += "\n\nBundle name: \(bundleName)"
        }
        if let version = plist["CFBundleShortVersionString"] as? String {
            output += "\nVersion: \(version)"
        }
        if let buildNumber = plist["CFBundleVersion"] as? String {
            output += "\nBuild: \(buildNumber)"
        }

        return CallTool.Result.text(output)
    }
}
