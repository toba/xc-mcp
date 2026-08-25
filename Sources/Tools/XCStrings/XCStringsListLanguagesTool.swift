import MCP
import XCMCPCore

public struct XCStringsListLanguagesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_list_languages",
            description: "List all languages in the xcstrings file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ])
                ]),
                "required": .array([.string("file")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            let languages = try await parser.listLanguages()

            let json = try encodePrettyJSON(languages, fallback: "[]")

            return CallTool.Result.text(json)
        }
    }
}
