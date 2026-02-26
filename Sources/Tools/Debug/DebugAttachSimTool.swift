import MCP
import XCMCPCore
import Foundation

public struct DebugAttachSimTool: Sendable {
    private let lldbRunner: LLDBRunner
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(
        lldbRunner: LLDBRunner = LLDBRunner(),
        simctlRunner: SimctlRunner = SimctlRunner(),
        sessionManager: SessionManager,
    ) {
        self.lldbRunner = lldbRunner
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_attach_sim",
            description:
            "Attach LLDB debugger to a running app on a simulator or macOS. "
                + "For simulator apps, provide bundle_id with a simulator UDID. "
                +
                "For macOS apps, provide bundle_id without a simulator — the PID is resolved automatically.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to debug.",
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified. "
                                + "Omit for macOS apps.",
                        ),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to attach to. Alternative to bundle_id.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get PID directly or look it up from bundle_id
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil {
            guard let bundleId = arguments.getString("bundle_id") else {
                throw MCPError.invalidParams("Either bundle_id or pid is required")
            }

            // Try to resolve simulator; if none available, treat as macOS app
            let simulator: String?
            if let value = arguments.getString("simulator") {
                simulator = value
            } else if let sessionSimulator = await sessionManager.simulatorUDID {
                simulator = sessionSimulator
            } else {
                simulator = nil
            }

            if let simulator {
                // Get PID of the running app on the simulator
                pid = try await findSimulatorAppPID(bundleId: bundleId, simulator: simulator)
            } else {
                // Get PID of the running macOS app
                pid = try await findMacOSAppPID(bundleId: bundleId)
            }
        }

        guard let targetPID = pid else {
            throw MCPError.internalError("Could not determine process ID to attach to")
        }

        do {
            let result = try await lldbRunner.attachToPID(targetPID)

            if result.succeeded || result.output.contains("Process") {
                // Register the bundle ID mapping
                if let bundleId = arguments.getString("bundle_id") {
                    await LLDBSessionManager.shared.registerBundleId(
                        bundleId, forPID: targetPID,
                    )
                }

                var message = "Successfully attached to process \(targetPID)\n\n"
                message += result.output

                return CallTool.Result(content: [
                    .text(message),
                ])
            } else {
                throw MCPError.internalError(
                    "Failed to attach to process: \(result.errorOutput)",
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func findSimulatorAppPID(bundleId: String, simulator: String) async throws -> Int32 {
        // Verify the app is installed on the simulator
        do {
            _ = try await simctlRunner.getAppContainer(
                udid: simulator, bundleId: bundleId, container: "app",
            )
        } catch {
            throw MCPError.invalidParams(
                "App '\(bundleId)' not found on simulator '\(simulator)'",
            )
        }

        // Use pgrep to find the process
        let result = try await ProcessResult.run("/usr/bin/pgrep", arguments: ["-f", bundleId])
        let output = result.stdout

        guard
            let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first,
            let pid = Int32(pidString)
        else {
            throw MCPError.internalError(
                "App '\(bundleId)' is not running on simulator '\(simulator)'. Launch it first with launch_app_sim.",
            )
        }

        return pid
    }

    private func findMacOSAppPID(bundleId: String) async throws -> Int32 {
        // Use pgrep to find the macOS app process by bundle ID
        let result = try await ProcessResult.run("/usr/bin/pgrep", arguments: ["-f", bundleId])
        let output = result.stdout

        guard
            let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first,
            let pid = Int32(pidString)
        else {
            throw MCPError.internalError(
                "macOS app '\(bundleId)' is not running. Launch it first with build_run_macos or launch_mac_app.",
            )
        }

        return pid
    }
}
