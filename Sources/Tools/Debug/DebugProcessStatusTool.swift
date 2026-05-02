import MCP
import XCMCPCore
import Foundation

public struct DebugProcessStatusTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_process_status",
            description:
            "Get the current process state of a debugged process.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }

        let bundleId = arguments.getString("bundle_id")

        do {
            let result = try await lldbRunner.processStatus(pid: targetPID)

            var message = "Process status for \(targetPID):\n\n\(result.output)"

            // If the process exited, auto-search for crash reports
            let output = result.output.lowercased()
            if output.contains("exited") || output.contains("crashed")
                || output.contains("signal")
            {
                CrashReportParser.appendCrashReports(
                    to: &message, bundleID: bundleId,
                )
            }

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }
}
