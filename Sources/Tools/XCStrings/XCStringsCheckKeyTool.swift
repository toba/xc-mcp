import MCP
import XCMCPCore
import Foundation

public struct XCStringsCheckKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_check_key",
            description: "Check if a key exists in the xcstrings file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to check"),
                    ]),
                    "language": .object([
                        "type": .string("string"),
                        "description": .string("Optional specific language to check"),
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
            let exists = try await parser.checkKey(key, language: language)

            let text: String

            if exists {
                text = "true"
            } else {
                let suggestions = try await parser.suggestions(for: key)

                if suggestions.isEmpty {
                    text = "false"
                } else {
                    let formatted = suggestions.map { "'\($0)'" }.joined(separator: ", ")
                    text = "false (key not found; did you mean: \(formatted)?)"
                }
            }

            return CallTool.Result.text(text)
        }
    }
}
