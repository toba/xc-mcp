import MCP
import XCMCPCore

public struct XCStringsBatchCheckKeysTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_batch_check_keys",
            description: "Check if multiple keys exist in an xcstrings file in one call",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "keys": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of keys to check"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Optional language to check translations for"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("keys")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let keys = arguments.getStringArray("keys")
        if keys.isEmpty {
            throw MCPError.invalidParams("keys array is required and cannot be empty")
        }
        let language = arguments.getString("language")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            let results = try await parser.checkKeys(keys, language: language)

            let batchResult = BatchCheckKeysResult(results: results)
            let json = try encodePrettyJSON(batchResult)

            return CallTool.Result.text(json)
        }
    }
}
