import MCP
import XCMCPCore

public struct XCStringsListUntranslatedTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_list_untranslated",
            description: "List untranslated keys for a specific language",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Language code to check"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("language")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let language = try arguments.getRequiredString("language")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            let untranslated = try await parser.listUntranslated(for: language)

            let json = try encodePrettyJSON(untranslated, fallback: "[]")

            return CallTool.Result.text(json)
        }
    }
}
