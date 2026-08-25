import MCP
import XCMCPCore
import Foundation

/// Tracks active video recording sessions
actor VideoRecordingManager {
    static let shared = VideoRecordingManager()

    private var activeSessions: [String: Process] = [:]

    func startRecording(sessionID: String, process: Process) { activeSessions[sessionID] = process }

    func stopRecording(sessionID: String) -> Process? {
        activeSessions.removeValue(forKey: sessionID)
    }

    func getActiveSessionIDs() -> [String] { Array(activeSessions.keys) }
}

public struct RecordSimVideoTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = .init(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "record_sim_video",
            description:
                "Start or stop video recording on a simulator. Use action 'start' to begin recording and 'stop' to end it.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("start"), .string("stop"), .string("list")]),
                        "description": .string(
                            "Action to perform: 'start' to begin recording, 'stop' to end recording, 'list' to show active recordings.",
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified.",
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for the output video file (e.g., '/tmp/recording.mp4'). Required for 'start' action.",
                        ),
                    ]),
                    "session_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Session ID returned from 'start' action. Required for 'stop' action.",
                        ),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let action = try arguments.getRequiredString("action")

        switch action {
            case "start": return try await startRecording(arguments: arguments)
            case "stop": return try await stopRecording(arguments: arguments)
            case "list": return await listRecordings()
            default:
                throw MCPError.invalidParams(
                    "Invalid action: \(action). Use 'start', 'stop', or 'list'.",
                )
        }
    }

    private func startRecording(arguments: [String: Value]) async throws -> CallTool.Result {
        guard let outputPath = arguments.getString("output_path") else {
            throw MCPError.invalidParams("output_path is required for 'start' action")
        }

        let simulator = try await sessionManager.resolveSimulator(from: arguments)

        do {
            let process = try simctlRunner.recordVideo(udid: simulator, outputPath: outputPath)
            let sessionID = UUID().uuidString

            await VideoRecordingManager.shared.startRecording(
                sessionID: sessionID, process: process,
            )

            return CallTool.Result.text(
                """
                Started video recording on simulator '\(simulator)'
                Output: \(outputPath)
                Session ID: \(sessionID)

                Use record_sim_video with action='stop' and session_id='\(
                sessionID
                )' to stop recording.
                """,
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    private func stopRecording(arguments: [String: Value]) async throws -> CallTool.Result {
        guard let sessionID = arguments.getString("session_id") else {
            throw MCPError.invalidParams("session_id is required for 'stop' action")
        }

        guard let process = await VideoRecordingManager.shared.stopRecording(sessionID: sessionID)
        else {
            throw MCPError.invalidParams(
                "No active recording found with session ID: \(sessionID). Use action='list' to see active recordings.",
            )
        }

        // Send SIGINT to gracefully stop the recording
        process.interrupt()

        // Wait for process to finish. waitUntilExit would park a cooperative worker while simctl
        // finalises the movie file.
        await process.waitForExit()

        return CallTool.Result.text("Stopped video recording. Session ID: \(sessionID)")
    }

    private func listRecordings() async -> CallTool.Result {
        let sessionIDs = await VideoRecordingManager.shared.getActiveSessionIDs()

        if sessionIDs.isEmpty { return CallTool.Result.text("No active video recordings.") }

        var output = "Active video recordings:\n"
        for sessionID in sessionIDs { output += "  - \(sessionID)\n" }

        return CallTool.Result.text(output)
    }
}
