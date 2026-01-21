import Foundation
import XCMCPCore
import MCP

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
                            "Path to the Swift package directory. Uses session default if not specified."
                        ),
                    ]),
                    "executable": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the executable to stop. Required to identify the process."),
                    ]),
                    "signal": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Signal to send: 'TERM' (graceful) or 'KILL' (force). Defaults to 'TERM'."
                        ),
                        "enum": .array([.string("TERM"), .string("KILL")]),
                    ]),
                ]),
                "required": .array([.string("executable")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        // Get executable name
        guard case let .string(executable) = arguments["executable"] else {
            throw MCPError.invalidParams("executable is required to identify the process to stop.")
        }

        // Get signal type
        let signal: String
        if case let .string(value) = arguments["signal"] {
            signal = value
        } else {
            signal = "TERM"
        }

        // Use pkill to find and stop the process
        let signalArg = signal == "KILL" ? "-9" : "-15"

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = [signalArg, "-f", executable]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully sent \(signal) signal to process '\(executable)'")
                    ]
                )
            } else if process.terminationStatus == 1 {
                // pkill returns 1 when no process found
                throw MCPError.invalidParams("No running process found matching '\(executable)'")
            } else {
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                throw MCPError.internalError("Failed to stop process: \(stderr)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Failed to stop process: \(error.localizedDescription)")
        }
    }
}
