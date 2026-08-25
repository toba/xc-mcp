import MCP
import XCMCPCore
import Foundation

/// Tracks active trace recording sessions.
actor TraceRecordingManager {
    static let shared = TraceRecordingManager()

    private var activeSessions: [String: (process: Process, outputPath: String)] = [:]

    func startRecording(sessionID: String, process: Process, outputPath: String) {
        activeSessions[sessionID] = (process: process, outputPath: outputPath)
    }

    func stopRecording(sessionID: String) -> (process: Process, outputPath: String)? {
        activeSessions.removeValue(forKey: sessionID)
    }

    func getActiveSessions() -> [(id: String, outputPath: String)] {
        activeSessions.map { (id: $0.key, outputPath: $0.value.outputPath) }
    }
}

/// Start, stop, or list xctrace trace recording sessions.
///
/// This tool manages long-running Instruments trace recordings using `xctrace record`. Recordings
/// can be started with a template (e.g., "Time Profiler", "Allocations"), optionally targeting a
/// specific device or process, and stopped later by session ID.
public struct XctraceRecordTool: Sendable {
    private let xctraceRunner: XctraceRunner
    private let sessionManager: SessionManager

    public init(xctraceRunner: XctraceRunner = .init(), sessionManager: SessionManager) {
        self.xctraceRunner = xctraceRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "xctrace_record",
            description: "Start, stop, or list Instruments trace recordings using xctrace.",
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
                    "template": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Instruments template name (e.g., 'Time Profiler', 'Allocations', 'Leaks'). Required for 'start' action. Use xctrace_list to see available templates.",
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for the output .trace file. Defaults to /tmp/trace_<timestamp>.trace if not specified.",
                        ),
                    ]),
                    "device": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Device name or UDID to record on. Omit to record on the local Mac.",
                        ),
                    ]),
                    "time_limit": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Auto-stop duration (e.g., '30s', '5m', '1h'). Recording stops automatically after this duration.",
                        ),
                    ]),
                    "attach_pid": .object([
                        "type": .string("string"),
                        "description": .string("Attach to a running process by PID."),
                    ]),
                    "attach_name": .object([
                        "type": .string("string"),
                        "description": .string("Attach to a running process by name."),
                    ]),
                    "all_processes": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Record system-wide across all processes. Default: false.",
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
        guard let template = arguments.getString("template") else {
            throw MCPError.invalidParams("template is required for 'start' action")
        }

        // Determine output path
        let outputPath: String

        if let path = arguments.getString("output_path") {
            outputPath = path
        } else {
            let timestamp = TimestampFormatting.iso8601.string(from: Date())
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
                allProcesses: allProcesses,
            )
            let sessionID = UUID().uuidString

            await TraceRecordingManager.shared.startRecording(
                sessionID: sessionID, process: process, outputPath: outputPath,
            )

            return CallTool.Result.text(
                """
                Started xctrace recording with template '\(template)'
                Output: \(outputPath)
                Session ID: \(sessionID)

                Use xctrace_record with action='stop' and session_id='\(
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

        guard let session = await TraceRecordingManager.shared.stopRecording(sessionID: sessionID)
        else {
            throw MCPError.invalidParams(
                "No active recording found with session ID: \(sessionID). Use action='list' to see active recordings.",
            )
        }

        // Send SIGINT to gracefully stop the recording
        session.process.interrupt()

        // Wait for process to finish. waitUntilExit would park a cooperative worker for as long as
        // xctrace takes to flush the trace.
        await session.process.waitForExit()

        return CallTool.Result.text(
            """
            Stopped xctrace recording.
            Session ID: \(sessionID)
            Output: \(session.outputPath)
            """,
        )
    }

    private func listRecordings() async -> CallTool.Result {
        let sessions = await TraceRecordingManager.shared.getActiveSessions()

        if sessions.isEmpty { return CallTool.Result.text("No active xctrace recordings.") }

        var output = "Active xctrace recordings:\n"
        for session in sessions { output += "  - \(session.id): \(session.outputPath)\n" }

        return CallTool.Result.text(output)
    }
}
