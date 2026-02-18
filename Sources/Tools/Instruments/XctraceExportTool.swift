import Foundation
import MCP
import XCMCPCore

/// Exports data from Instruments `.trace` files.
///
/// This tool uses `xctrace export` to extract data from trace files as XML.
/// Use `toc=true` to see the table of contents (available data tables),
/// then use `xpath` to query specific tables.
///
/// ## Typical Workflow
///
/// 1. `xctrace_export input_path=... toc=true` — see available tables
/// 2. `xctrace_export input_path=... xpath='/trace-toc/run/data/table[@schema="time-profile"]'` — extract data
public struct XctraceExportTool: Sendable {
    private let xctraceRunner: XctraceRunner

    public init(xctraceRunner: XctraceRunner = XctraceRunner()) {
        self.xctraceRunner = xctraceRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "xctrace_export",
            description:
                "Export data from an Instruments .trace file as XML. Use toc=true to see available tables, then use xpath to query specific data.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "input_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .trace file to export from."),
                    ]),
                    "xpath": .object([
                        "type": .string("string"),
                        "description": .string(
                            "XPath query for specific data tables (e.g., '/trace-toc/run/data/table[@schema=\"time-profile\"]')."
                        ),
                    ]),
                    "toc": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Show the table of contents of the trace file. Default: false. Used when xpath is not provided."
                        ),
                    ]),
                ]),
                "required": .array([.string("input_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard case let .string(inputPath) = arguments["input_path"] else {
            throw MCPError.invalidParams("input_path is required")
        }

        let xpath: String?
        if case let .string(value) = arguments["xpath"] {
            xpath = value
        } else {
            xpath = nil
        }

        let toc: Bool
        if case let .bool(value) = arguments["toc"] {
            toc = value
        } else {
            toc = xpath == nil  // Default to toc when no xpath provided
        }

        do {
            let result = try await xctraceRunner.export(
                inputPath: inputPath,
                xpath: xpath,
                toc: toc
            )

            guard result.succeeded else {
                throw MCPError.internalError("xctrace export failed: \(result.stderr)")
            }

            let output = result.stdout.isEmpty ? result.stderr : result.stdout
            return CallTool.Result(content: [.text(output)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to export trace: \(error.localizedDescription)")
        }
    }
}
