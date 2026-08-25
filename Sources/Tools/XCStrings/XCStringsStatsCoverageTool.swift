import MCP
import XCMCPCore

public struct XCStringsStatsCoverageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let compact = arguments.getBool("compact", default: true)

        return try await pathUtility.withParser(at: filePath) { parser, _ in

            let json: String

            if compact {
                let stats = try await parser.getCompactStats()
                json = try encodePrettyJSON(stats)
            } else {
                let stats = try await parser.getStats()
                json = try encodePrettyJSON(stats)
            }

            return CallTool.Result.text(json)
        }
    }
}
