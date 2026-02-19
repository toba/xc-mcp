import Foundation
import MCP
import XCMCPCore

/// Tracks active trace recording sessions.
actor TraceRecordingManager {
    static let shared = TraceRecordingManager()

    private var activeSessions: [String: (process: Process, outputPath: String)] = [:]

    func startRecording(sessionId: String, process: Process, outputPath: String) {
        activeSessions[sessionId] = (process: process, outputPath: outputPath)
    }

    func stopRecording(sessionId: String) -> (process: Process, outputPath: String)? {
        return activeSessions.removeValue(forKey: sessionId)
    }

    func getActiveSessions() -> [(id: String, outputPath: String)] {
        return activeSessions.map { (id: $0.key, outputPath: $0.value.outputPath) }
    }
}

/// Start, stop, or list xctrace trace recording sessions.
///
/// This tool manages long-running Instruments trace recordings using `xctrace record`.
/// Recordings can be started with a template (e.g., "Time Profiler", "Allocations"),
/// optionally targeting a specific device or process, and stopped later by session ID.
public struct XctraceRecordTool: Sendable {
    private let xctraceRunner: XctraceRunner
    private let sessionManager: SessionManager

    public init(xctraceRunner: XctraceRunner = XctraceRunner(), sessionManager: SessionManager) {
        self.xctraceRunner = xctraceRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "xctrace_record",
            description:
                "Start or stop an Instruments trace recording using xctrace. Use action 'start' to begin profiling with a template (e.g., Time Profiler, Allocations), 'stop' to end a recording, or 'list' to show active sessions.",
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
                    "template": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Instruments template name (e.g., 'Time Profiler', 'Allocations', 'Leaks'). Required for 'start' action. Use xctrace_list to see available templates."
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for the output .trace file. Defaults to /tmp/trace_<timestamp>.trace if not specified."
                        ),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device name or UDID to record on. Omit to record on the local Mac."
                        ),
                    ]),
                    "time_limit": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Auto-stop duration (e.g., '30s', '5m', '1h'). Recording stops automatically after this duration."
                        ),
                    ]),
                    "attach_pid": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Attach to a running process by PID."),
                    ]),
                    "attach_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Attach to a running process by name."),
                    ]),
                    "all_processes": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Record system-wide across all processes. Default: false."),
                    ]),
                    "session_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Session ID returned from 'start' action. Required for 'stop' action."
                        ),
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
        guard case let .string(template) = arguments["template"] else {
            throw MCPError.invalidParams("template is required for 'start' action")
        }

        // Determine output path
        let outputPath: String
        if case let .string(path) = arguments["output_path"] {
            outputPath = path
        } else {
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            outputPath = "/tmp/trace_\(timestamp).trace"
        }

        // Extract optional parameters
        let device = arguments.getString("device")
        let timeLimit = arguments.getString("time_limit")
        let attachPID = arguments.getString("attach_pid")
        let attachName = arguments.getString("attach_name")
        let allProcesses = arguments.getBool("all_processes")

        do {
            let process = try xctraceRunner.record(
                template: template,
                outputPath: outputPath,
                device: device,
                timeLimit: timeLimit,
                attachPID: attachPID,
                attachName: attachName,
                allProcesses: allProcesses
            )
            let sessionId = UUID().uuidString

            await TraceRecordingManager.shared.startRecording(
                sessionId: sessionId, process: process, outputPath: outputPath)

            return CallTool.Result(
                content: [
                    .text(
                        """
                        Started xctrace recording with template '\(template)'
                        Output: \(outputPath)
                        Session ID: \(sessionId)

                        Use xctrace_record with action='stop' and session_id='\(sessionId)' to stop recording.
                        """
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to start xctrace recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(sessionId) = arguments["session_id"] else {
            throw MCPError.invalidParams("session_id is required for 'stop' action")
        }

        guard
            let session = await TraceRecordingManager.shared.stopRecording(sessionId: sessionId)
        else {
            throw MCPError.invalidParams(
                "No active recording found with session ID: \(sessionId). Use action='list' to see active recordings."
            )
        }

        // Send SIGINT to gracefully stop the recording
        session.process.interrupt()

        // Wait for process to finish
        session.process.waitUntilExit()

        return CallTool.Result(
            content: [
                .text(
                    """
                    Stopped xctrace recording.
                    Session ID: \(sessionId)
                    Output: \(session.outputPath)
                    """
                )
            ]
        )
    }

    private func listRecordings() async -> CallTool.Result {
        let sessions = await TraceRecordingManager.shared.getActiveSessions()

        if sessions.isEmpty {
            return CallTool.Result(
                content: [.text("No active xctrace recordings.")]
            )
        }

        var output = "Active xctrace recordings:\n"
        for session in sessions {
            output += "  - \(session.id): \(session.outputPath)\n"
        }

        return CallTool.Result(content: [.text(output)])
    }
}
