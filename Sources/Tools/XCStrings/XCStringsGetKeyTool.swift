import MCP
import XCMCPCore

public struct XCStringsGetKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_get_key",
            description: "Get translations for a specific key",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to get translations for"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Optional specific language to get"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")
        let language = arguments.getString("language")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            let translations = try await parser.getTranslation(key: key, language: language)

            let json = try encodePrettyJSON(translations)

            return CallTool.Result.text(json)
        }
    }
}
