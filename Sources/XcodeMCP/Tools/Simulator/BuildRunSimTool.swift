import Foundation
import MCP

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

        // Get simulator
        let simulator: String
        if case let .string(value) = arguments["simulator"] {
            simulator = value
        } else if let sessionSimulator = await sessionManager.simulatorUDID {
            simulator = sessionSimulator
        } else {
            throw MCPError.invalidParams(
                "simulator is required. Set it with set_session_defaults or pass it directly.")
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

        // Get optional bundle ID
        let bundleId: String?
        if case let .string(value) = arguments["bundle_id"] {
            bundleId = value
        } else {
            bundleId = nil
        }

        // Validate we have either project or workspace
        if projectPath == nil && workspacePath == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

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
                let errorOutput = extractBuildErrors(from: buildResult.output)
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

    private func extractBuildErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("BUILD FAILED")
        }

        if errorLines.isEmpty {
            return lines.suffix(20).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }

    private func extractBundleId(from buildSettings: String) -> String? {
        // Look for PRODUCT_BUNDLE_IDENTIFIER in the build settings JSON
        let lines = buildSettings.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("PRODUCT_BUNDLE_IDENTIFIER") {
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
