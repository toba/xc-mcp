import MCP
import XCMCPCore
import Foundation

/// Samples a running macOS process to capture call stacks.
///
/// Wraps the `/usr/bin/sample` command and parses the output into a structured
/// summary with heaviest functions and call paths, filtered to app code by default.
///
/// ## Example
///
/// ```
/// sample_mac_app(pid: 12345, duration: 5)
/// sample_mac_app(bundle_id: "com.example.MyApp", duration: 10, filter: "all")
/// ```
public struct SampleMacAppTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "sample_mac_app",
            description:
            "Sample a running macOS app to capture call stacks for performance analysis. Returns parsed summary with heaviest functions and call paths, filtered to app code by default. Use filter='all' to include system frames.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID to sample. Use this or bundle_id.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app to sample (e.g., 'com.example.MyApp'). Resolved to PID internally.",
                        ),
                    ]),
                    "duration": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Sampling duration in seconds. Default: 5.",
                        ),
                    ]),
                    "interval": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Sampling interval in milliseconds. Default: 1 (1ms).",
                        ),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "enum": .array([.string("app"), .string("all")]),
                        "description": .string(
                            "Frame filter: 'app' (default) shows only app code, 'all' includes system frameworks.",
                        ),
                    ]),
                    "top_n": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Number of heaviest functions/paths to return. Default: 20.",
                        ),
                    ]),
                    "thread": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Thread filter: 'main' (default), 'all', or a thread name substring.",
                        ),
                    ]),
                    "raw": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Return raw sample output without parsing. Default: false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid: Int
        if let directPID = arguments.getInt("pid") {
            pid = directPID
        } else if let bundleId = arguments.getString("bundle_id") {
            guard let resolved = await PIDResolver.findPID(matching: bundleId) else {
                throw MCPError.invalidParams(
                    "No running process found for bundle ID '\(bundleId)'. Is the app running?",
                )
            }
            pid = Int(resolved)
        } else {
            throw MCPError.invalidParams("Either pid or bundle_id is required.")
        }

        let duration = arguments.getInt("duration") ?? 5
        let interval = arguments.getInt("interval") ?? 1

        do {
            let result = try await ProcessResult.run(
                "/usr/bin/sample",
                arguments: ["\(pid)", "\(duration)", "\(interval)"],
                timeout: .seconds(duration + 30),
            )

            guard result.succeeded else {
                throw MCPError.internalError(
                    "sample failed (exit \(result.exitCode)): \(result.stderr)",
                )
            }

            let rawOutput = result.stdout.isEmpty ? result.stderr : result.stdout

            // Return raw output if requested
            if arguments.getBool("raw") {
                return CallTool.Result(content: [.text(rawOutput)])
            }

            // Parse and summarize
            let filter = arguments.getString("filter") ?? "app"
            let topN = arguments.getInt("top_n") ?? 20
            let thread = arguments.getString("thread") ?? "main"

            let summary = SampleOutputParser.summarize(
                rawOutput: rawOutput,
                filter: filter,
                topN: topN,
                thread: thread,
            )

            return CallTool.Result(content: [.text(summary)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to sample process \(pid): \(error.localizedDescription)",
            )
        }
    }
}
