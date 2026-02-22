import MCP
import XCMCPCore
import Foundation

public struct XCStringsStatsCoverageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_stats_coverage",
            description:
            "Get overall translation statistics. Use compact mode to only show languages under 100%.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "compact": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, only show languages under 100% coverage (default: true)",
                        ),
                    ]),
                ]),
                "required": .array([.string("file")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let compact = arguments.getBool("compact", default: true)

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let json: String
            if compact {
                let stats = try await parser.getCompactStats()
                let data = try encoder.encode(stats)
                json = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                let stats = try await parser.getStats()
                let data = try encoder.encode(stats)
                json = String(data: data, encoding: .utf8) ?? "{}"
            }

            return CallTool.Result(content: [.text(json)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
