import Foundation
import MCP
import XCMCPCore

public struct StartMacLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "start_mac_log_cap",
            description:
                "Start capturing logs from a macOS app using the unified logging system. Logs are written to a file and can be stopped with stop_mac_log_cap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional bundle identifier to filter logs to a specific app."),
                    ]),
                    "process_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional process name to filter logs to a specific process."),
                    ]),
                    "subsystem": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional OSLog subsystem to filter logs (e.g., 'com.apple.CloudKit')."
                        ),
                    ]),
                    "predicate": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional custom predicate to filter logs. Overrides bundle_id, process_name, and subsystem filters."
                        ),
                    ]),
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write logs to. Defaults to /tmp/mac_log_<identifier>.log"),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundleId = arguments.getString("bundle_id")
        let processName = arguments.getString("process_name")
        let subsystem = arguments.getString("subsystem")
        let customPredicate = arguments.getString("predicate")
        let outputFile = arguments.getString("output_file")
            ?? "/tmp/mac_log_\(bundleId ?? processName ?? "system").log"

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")

            var args = ["stream", "--style", "compact"]

            // Build predicate
            if let customPredicate {
                args.append(contentsOf: ["--predicate", customPredicate])
            } else {
                var predicateParts: [String] = []

                if let bundleId {
                    predicateParts.append("processImagePath CONTAINS \"\(bundleId)\"")
                }
                if let processName {
                    predicateParts.append("process == \"\(processName)\"")
                }
                if let subsystem {
                    predicateParts.append("subsystem == \"\(subsystem)\"")
                }

                if !predicateParts.isEmpty {
                    args.append(contentsOf: [
                        "--predicate", predicateParts.joined(separator: " AND "),
                    ])
                }
            }

            process.arguments = args

            // Set up file output
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: outputFile) {
                fileManager.createFile(atPath: outputFile, contents: nil)
            }

            guard let fileHandle = FileHandle(forWritingAtPath: outputFile) else {
                throw MCPError.internalError("Failed to open output file: \(outputFile)")
            }
            fileHandle.seekToEndOfFile()

            process.standardOutput = fileHandle
            process.standardError = fileHandle

            try process.run()

            let pid = process.processIdentifier

            var message = "Started macOS log capture\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let bundleId {
                message += "Filtering for bundle: \(bundleId)\n"
            }
            if let processName {
                message += "Filtering for process: \(processName)\n"
            }
            if let subsystem {
                message += "Filtering for subsystem: \(subsystem)\n"
            }
            message += "\nUse stop_mac_log_cap to stop the capture."

            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
