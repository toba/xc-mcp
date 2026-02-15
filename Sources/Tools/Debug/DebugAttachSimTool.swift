import Foundation
import MCP
import XCMCPCore

public struct DebugAttachSimTool: Sendable {
    private let lldbRunner: LLDBRunner
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(
        lldbRunner: LLDBRunner = LLDBRunner(),
        simctlRunner: SimctlRunner = SimctlRunner(),
        sessionManager: SessionManager
    ) {
        self.lldbRunner = lldbRunner
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_attach_sim",
            description:
                "Attach LLDB debugger to a running app on a simulator.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to debug."),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to attach to. Alternative to bundle_id."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get PID directly or look it up from bundle_id
        var pid: Int32?

        if case let .int(value) = arguments["pid"] {
            pid = Int32(value)
        }

        if pid == nil {
            guard case let .string(bundleId) = arguments["bundle_id"] else {
                throw MCPError.invalidParams("Either bundle_id or pid is required")
            }

            // Get simulator
            let simulator: String
            if case let .string(value) = arguments["simulator"] {
                simulator = value
            } else if let sessionSimulator = await sessionManager.simulatorUDID {
                simulator = sessionSimulator
            } else {
                throw MCPError.invalidParams(
                    "simulator is required when using bundle_id. Set it with set_session_defaults or pass it directly."
                )
            }

            // Get PID of the running app on the simulator
            pid = try await findAppPID(bundleId: bundleId, simulator: simulator)
        }

        guard let targetPID = pid else {
            throw MCPError.internalError("Could not determine process ID to attach to")
        }

        do {
            let result = try await lldbRunner.attachToPID(targetPID)

            if result.succeeded || result.output.contains("Process") {
                // Register the bundle ID mapping
                if case let .string(bundleId) = arguments["bundle_id"] {
                    await LLDBSessionManager.shared.registerBundleId(
                        bundleId, forPID: targetPID)
                }

                var message = "Successfully attached to process \(targetPID)\n\n"
                message += result.output

                return CallTool.Result(content: [.text(message)])
            } else {
                throw MCPError.internalError(
                    "Failed to attach to process: \(result.stderr.isEmpty ? result.stdout : result.stderr)"
                )
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func findAppPID(bundleId: String, simulator: String) async throws -> Int32 {
        // Use simctl to find the app's PID
        // First, try to get the app container to verify it's installed
        do {
            _ = try await simctlRunner.getAppContainer(
                udid: simulator, bundleId: bundleId, container: "app")
        } catch {
            throw MCPError.invalidParams(
                "App '\(bundleId)' not found on simulator '\(simulator)'")
        }

        // Use pgrep to find the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", bundleId]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard
            let pidString = output.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first,
            let pid = Int32(pidString)
        else {
            throw MCPError.internalError(
                "App '\(bundleId)' is not running on simulator '\(simulator)'. Launch it first with launch_app_sim."
            )
        }

        return pid
    }
}
