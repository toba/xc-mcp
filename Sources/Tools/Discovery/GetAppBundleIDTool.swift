import MCP
import XCMCPCore
import Foundation

public struct GetAppBundleIDTool: Sendable {
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
            name: "get_app_bundle_id",
            description:
                "Get the bundle identifier for an iOS/tvOS/watchOS app target from build settings.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
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
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)
        let scheme = try await sessionManager.resolveScheme(from: arguments)
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

                var output = "Bundle identifier for scheme '\(scheme)' "
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
}
