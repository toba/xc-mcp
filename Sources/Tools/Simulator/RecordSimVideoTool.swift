import Foundation
import MCP

/// Tracks active video recording sessions
actor VideoRecordingManager {
    static let shared = VideoRecordingManager()

    private var activeSessions: [String: Process] = [:]

    func startRecording(sessionId: String, process: Process) {
        activeSessions[sessionId] = process
    }

    func stopRecording(sessionId: String) -> Process? {
        return activeSessions.removeValue(forKey: sessionId)
    }

    func getActiveSessionIds() -> [String] {
        return Array(activeSessions.keys)
    }
}

public struct RecordSimVideoTool: Sendable {
    private let simctlRunner: SimctlRunner
    private let sessionManager: SessionManager

    public init(simctlRunner: SimctlRunner = SimctlRunner(), sessionManager: SessionManager) {
        self.simctlRunner = simctlRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
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
                            "Action to perform: 'start' to begin recording, 'stop' to end recording, 'list' to show active recordings."
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for the output video file (e.g., '/tmp/recording.mp4'). Required for 'start' action."
                        ),
                    ]),
                    "session_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Session ID returned from 'start' action. Required for 'stop' action."),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(action) = arguments["action"] else {
            throw MCPError.invalidParams("action is required")
        }

        switch action {
        case "start":
            return try await startRecording(arguments: arguments)
        case "stop":
            return try await stopRecording(arguments: arguments)
        case "list":
            return try await listRecordings()
        default:
            throw MCPError.invalidParams(
                "Invalid action: \(action). Use 'start', 'stop', or 'list'.")
        }
    }

    private func startRecording(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(outputPath) = arguments["output_path"] else {
            throw MCPError.invalidParams("output_path is required for 'start' action")
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

        do {
            let process = try await simctlRunner.recordVideo(
                udid: simulator, outputPath: outputPath)
            let sessionId = UUID().uuidString

            await VideoRecordingManager.shared.startRecording(
                sessionId: sessionId, process: process)

            return CallTool.Result(
                content: [
                    .text(
                        """
                        Started video recording on simulator '\(simulator)'
                        Output: \(outputPath)
                        Session ID: \(sessionId)

                        Use record_sim_video with action='stop' and session_id='\(sessionId)' to stop recording.
                        """
                    )
                ]
            )
        } catch {
            throw MCPError.internalError("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(sessionId) = arguments["session_id"] else {
            throw MCPError.invalidParams("session_id is required for 'stop' action")
        }

        guard let process = await VideoRecordingManager.shared.stopRecording(sessionId: sessionId)
        else {
            throw MCPError.invalidParams(
                "No active recording found with session ID: \(sessionId). Use action='list' to see active recordings."
            )
        }

        // Send SIGINT to gracefully stop the recording
        process.interrupt()

        // Wait for process to finish
        process.waitUntilExit()

        return CallTool.Result(
            content: [
                .text("Stopped video recording. Session ID: \(sessionId)")
            ]
        )
    }

    private func listRecordings() async -> CallTool.Result {
        let sessionIds = await VideoRecordingManager.shared.getActiveSessionIds()

        if sessionIds.isEmpty {
            return CallTool.Result(
                content: [.text("No active video recordings.")]
            )
        }

        var output = "Active video recordings:\n"
        for sessionId in sessionIds {
            output += "  - \(sessionId)\n"
        }

        return CallTool.Result(content: [.text(output)])
    }
}
