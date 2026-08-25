import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct BuildRunSimTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        simctlRunner: SimctlRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "build_run_sim",
            description:
                "Build and run an Xcode project or workspace on the iOS/tvOS/watchOS Simulator. This combines build_sim, install_app_sim, and launch_app_sim into a single operation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
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
                                "The scheme to build. Uses session default if not specified.",
                            ),
                        ]),
                        "simulator": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Simulator UDID or name. Uses session default if not specified.",
                            ),
                        ]),
                        "configuration": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                        "bundle_id": .object([
                            "type": .string("string"),
                            "description": .string(
                                "Bundle identifier of the app to launch. If not provided, will be derived from build settings.",
                            ),
                        ]),
                    ].merging([String: Value].continueBuildingSchemaProperty) { _, new in new }
                        .merging([String: Value].buildSettingsSchemaProperty) { _, new in new }
                        .merging([String: Value].extraArgsSchemaProperty) { _, new in new }
                        .merging([String: Value].timeoutSchemaProperty(defaultSeconds: 300)) {
                            _, new in new
                        }
                        .merging([String: Value].outputTimeoutSchemaProperty(defaultSeconds: 120)) {
                            _, new in new
                        },
                ),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        // Resolve parameters from arguments or session defaults
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let simulatorInput = try await sessionManager.resolveSimulator(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let bundleID = arguments.getString("bundle_id")
        let timeout = arguments.resolveTimeout(default: XcodebuildRunner.defaultTimeout)
        let outputTimeout = arguments.resolveOutputTimeout(
            default: XcodebuildRunner.deviceOutputTimeout,
        )

        do {
            // Resolve the simulator to its canonical UDID + runtime-derived destination so
            // visionOS/watchOS/tvOS simulators don't build against an iOS destination.
            let resolved = try await simctlRunner.resolveForBuild(matching: simulatorInput)
            let simulator = resolved.udid
            let destination = resolved.destination
            let extraArgs = await sessionManager.resolveExtraArgs(from: arguments)
            let additionalArguments = arguments.continueBuildingArgs()
                + arguments.buildSettingOverrides() + extraArgs
            let derivedDataNote = DerivedDataScoper.note(
                workspacePath: workspacePath,
                projectPath: projectPath,
                destination: destination,
                additionalArguments: additionalArguments,
            )

            // Step 1: Build (use longer output timeout — linking/signing phases routinely produce
            // no output for >30 seconds)
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration,
                additionalArguments: additionalArguments,
                environment: environment,
                timeout: timeout,
                outputTimeout: outputTimeout,
                onProgress: onProgress,
            )

            try ErrorExtractor.checkBuildSuccess(
                buildResult,
                projectRoot: ErrorExtractor.projectRoot(
                    projectPath: projectPath, workspacePath: workspacePath,
                ),
                derivedDataNote: derivedDataNote,
            )

            // Step 2: Get bundle ID and app path from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
                destination: destination,
                outputTimeout: outputTimeout,
            )

            // One decode serves every lookup below; the payload runs to megabytes.
            let settings = BuildSettingSet(buildSettings.stdout)
            let resolvedBundleID: String
            let appPath: String

            if let providedBundleID = bundleID {
                resolvedBundleID = providedBundleID
                appPath = settings.appPath ?? ""
            } else {
                guard let extractedBundleID = settings.bundleID else {
                    throw MCPError.internalError(
                        "Could not determine bundle ID. Please provide bundle_id parameter.",
                    )
                }
                resolvedBundleID = extractedBundleID
                appPath = settings.appPath ?? ""
            }

            // Step 3: Boot simulator if needed
            let devices = try await simctlRunner.listDevices()
            if let device = devices.first(where: { $0.udid == simulator }),
               device.state != "Booted" { _ = try await simctlRunner.boot(udid: simulator) }

            // Step 4: Install app
            if !appPath.isEmpty {
                let installResult = try await simctlRunner.install(
                    udid: simulator, appPath: appPath,
                )

                if !installResult.succeeded {
                    throw MCPError.internalError(
                        "Failed to install app: \(installResult.errorOutput)",
                    )
                }
            }

            // Step 5: Launch app
            let launchResult = try await simctlRunner.launch(
                udid: simulator,
                bundleID: resolvedBundleID,
            )

            if launchResult.succeeded {
                var message =
                    "Successfully built and launched '\(resolvedBundleID)' on simulator '\(simulator)'"
                if let pid = launchResult.launchedPID { message += "\nProcess ID: \(pid)" }
                message += "\n\n" + derivedDataNote
                return CallTool.Result.text(message)
            } else {
                throw MCPError.internalError("Failed to launch app: \(launchResult.errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
