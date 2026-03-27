import MCP
import XCMCPCore
import Foundation

public struct DeployDeviceTool: Sendable {
    private let deviceCtlRunner: DeviceCtlRunner
    private let sessionManager: SessionManager

    public init(
        deviceCtlRunner: DeviceCtlRunner = DeviceCtlRunner(), sessionManager: SessionManager,
    ) {
        self.deviceCtlRunner = deviceCtlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "deploy_device",
            description:
            "Deploy an app to a connected device: stop any running instance, install the .app bundle, and launch it. Combines stop_app_device + install_app_device + launch_app_device into a single call.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .app bundle to install.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app. Required to stop any running instance and to launch after install.",
                        ),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device UDID. Uses session default if not specified.",
                        ),
                    ]),
                ]),
                "required": .array([.string("app_path"), .string("bundle_id")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let appPath = try arguments.getRequiredString("app_path")
        let bundleId = try arguments.getRequiredString("bundle_id")
        let device = try await sessionManager.resolveDevice(from: arguments)

        var steps: [String] = []

        do {
            // Step 1: Stop any running instance (ignore errors — app may not be running)
            do {
                _ = try await deviceCtlRunner.terminate(udid: device, bundleId: bundleId)
                steps.append("✓ Stopped running instance of '\(bundleId)'")
            } catch {
                switch error {
                    case .processNotFound:
                        steps.append("– No running instance of '\(bundleId)' to stop")
                    default:
                        steps.append("⚠ Could not stop app: \(error.localizedDescription)")
                }
            }

            // Step 2: Install
            let installResult = try await deviceCtlRunner.install(
                udid: device, appPath: appPath,
            )
            guard installResult.succeeded else {
                throw MCPError.internalError(
                    "Install failed: \(installResult.errorOutput)",
                )
            }
            steps.append("✓ Installed '\(appPath)'")

            // Step 3: Launch
            let launchResult = try await deviceCtlRunner.launch(
                udid: device, bundleId: bundleId,
            )
            guard launchResult.succeeded else {
                throw MCPError.internalError(
                    "Launch failed: \(launchResult.errorOutput)",
                )
            }
            steps.append("✓ Launched '\(bundleId)'")

            let summary = steps.joined(separator: "\n")
            return CallTool.Result(
                content: [
                    .text(
                        "Deploy succeeded on device '\(device)'\n\n\(summary)",
                    ),
                ],
            )
        } catch {
            let progress = steps.isEmpty ? "" : "\n\nProgress:\n\(steps.joined(separator: "\n"))"
            throw MCPError.internalError(
                "Deploy failed: \(error.localizedDescription)\(progress)",
            )
        }
    }
}
