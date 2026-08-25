import MCP
import XCMCPCore
import Foundation

public struct XCStringsGetSourceLanguageTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_get_source_language",
            description: "Get the source language of the xcstrings file",
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
            let sourceLanguage = try await parser.getSourceLanguage()

            return CallTool.Result.text(sourceLanguage)
        }
    }
}
