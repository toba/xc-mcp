import MCP
import XCMCPCore
import Foundation

public struct StartMacLogCapTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) { self.sessionManager = sessionManager }

    public func tool() -> Tool {
        .init(
            name: "start_mac_log_cap",
            description:
                "Start capturing logs from a macOS app using the unified logging system. Logs are written to a file and can be stopped with stop_mac_log_cap.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(UnifiedLogQuery.schemaProperties.merging([
                    "output_file": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to write logs to. Defaults to /tmp/mac_log_<identifier>.log",
                        ),
                    ])
                ]) { _, new in new },
                ),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let query = try UnifiedLogQuery(arguments: arguments)
            let outputFile = arguments.getString("output_file")
                ?? "/tmp/mac_log_\(query.bundleID ?? query.processName ?? "system").log"

            let predicate = await query.resolvedPredicate()
            let args = query.commandArguments(subcommand: "stream", predicate: predicate)

            let pid = try LogCapture.launchStreamProcess(
                executable: "/usr/bin/log", arguments: args, outputFile: outputFile,
            )

            // Verify the log stream process is still running after a brief delay
            try await LogCapture.verifyStreamHealth(pid: pid, outputFile: outputFile)

            var message = "Started macOS log capture\n"
            message += "Output file: \(outputFile)\n"
            message += "Process ID: \(pid)\n"
            if let predicate { message += "Predicate: \(predicate)\n" }
            if let level = query.level, level != .default {
                message += "Level: \(level.rawValue) (includes \(level.rawValue) and above)\n"
            }
            message += "\nUse stop_mac_log_cap to stop the capture."

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
