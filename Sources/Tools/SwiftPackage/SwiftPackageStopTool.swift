import MCP
import XCMCPCore
import Foundation

public struct SwiftPackageStopTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_stop",
            description:
            "Stop a running Swift package executable that was started via swift_package_run. Uses process termination to stop the executable.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory. Uses session default if not specified.",
                        ),
                    ]),
                    "executable": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the executable to stop. Required to identify the process.",
                        ),
                    ]),
                    "signal": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Signal to send: 'TERM' (graceful) or 'KILL' (force). Defaults to 'TERM'.",
                        ),
                        "enum": .array([.string("TERM"), .string("KILL")]),
                    ]),
                ]),
                "required": .array([.string("executable")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        // Get executable name
        guard case let .string(executable) = arguments["executable"] else {
            throw MCPError.invalidParams("executable is required to identify the process to stop.")
        }

        // Get signal type
        let signal = arguments.getString("signal") ?? "TERM"

        // Use pkill to find and stop the process
        let signalArg = signal == "KILL" ? "-9" : "-15"

        do {
            let result = try ProcessResult.run(
                "/usr/bin/pkill", arguments: [signalArg, "-f", executable], mergeStderr: false,
            )

            if result.succeeded {
                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully sent \(signal) signal to process '\(executable)'",
                        ),
                    ],
                )
            } else if result.exitCode == 1 {
                // pkill returns 1 when no process found
                throw MCPError.invalidParams("No running process found matching '\(executable)'")
            } else {
                throw MCPError.internalError("Failed to stop process: \(result.stderr)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
