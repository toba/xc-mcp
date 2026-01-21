import Foundation
import MCP
import XCMCPCore

public struct BuildRunSimTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        simctlRunner: SimctlRunner = SimctlRunner(),
        sessionManager: SessionManager
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "build_run_sim",
            description:
                "Build and run an Xcode project or workspace on the iOS/tvOS/watchOS Simulator. This combines build_sim, install_app_sim, and launch_app_sim into a single operation.",
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
                            "The scheme to build. Uses session default if not specified."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to launch. If not provided, will be derived from build settings."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments)
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let simulator = try await sessionManager.resolveSimulator(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let bundleId = arguments.getString("bundle_id")

        do {
            let destination = "platform=iOS Simulator,id=\(simulator)"

            // Step 1: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration
            )

            if !buildResult.succeeded {
                let errorOutput = ErrorExtractor.extractBuildErrors(from: buildResult.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 2: Get bundle ID and app path from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            let resolvedBundleId: String
            let appPath: String

            if let providedBundleId = bundleId {
                resolvedBundleId = providedBundleId
                appPath = extractAppPath(from: buildSettings.stdout) ?? ""
            } else {
                guard let extractedBundleId = extractBundleId(from: buildSettings.stdout) else {
                    throw MCPError.internalError(
                        "Could not determine bundle ID. Please provide bundle_id parameter.")
                }
                resolvedBundleId = extractedBundleId
                appPath = extractAppPath(from: buildSettings.stdout) ?? ""
            }

            // Step 3: Install app
            if !appPath.isEmpty {
                let installResult = try await simctlRunner.install(
                    udid: simulator, appPath: appPath)
                if !installResult.succeeded {
                    throw MCPError.internalError(
                        "Failed to install app: \(installResult.stderr.isEmpty ? installResult.stdout : installResult.stderr)"
                    )
                }
            }

            // Step 4: Launch app
            let launchResult = try await simctlRunner.launch(
                udid: simulator,
                bundleId: resolvedBundleId
            )

            if launchResult.succeeded {
                var message =
                    "Successfully built and launched '\(resolvedBundleId)' on simulator '\(simulator)'"
                if let pid = extractPID(from: launchResult.stdout) {
                    message += "\nProcess ID: \(pid)"
                }
                return CallTool.Result(content: [.text(message)])
            } else {
                throw MCPError.internalError(
                    "Failed to launch app: \(launchResult.stderr.isEmpty ? launchResult.stdout : launchResult.stderr)"
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Build and run failed: \(error.localizedDescription)")
        }
    }

    private func extractBundleId(from buildSettings: String) -> String? {
        // Look for PRODUCT_BUNDLE_IDENTIFIER in the build settings JSON
        let lines = buildSettings.components(separatedBy: .newlines)
        for line in lines where line.contains("PRODUCT_BUNDLE_IDENTIFIER") {
            // Extract value after the key
            if let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER") {
                let afterKey = String(line[range.upperBound...])
                let cleaned = afterKey.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && !cleaned.hasPrefix("$") {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        // Look for CODESIGNING_FOLDER_PATH or similar
        let lines = buildSettings.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("CODESIGNING_FOLDER_PATH") || line.contains("TARGET_BUILD_DIR") {
                if let range = line.range(of: "/") {
                    let path = String(line[range.lowerBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "\"", with: "")
                        .replacingOccurrences(of: ",", with: "")
                    if path.hasSuffix(".app") {
                        return path
                    }
                }
            }
        }
        return nil
    }

    private func extractPID(from output: String) -> String? {
        let components = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ": ")
        if components.count >= 2 {
            return components.last
        }
        return nil
    }
}
