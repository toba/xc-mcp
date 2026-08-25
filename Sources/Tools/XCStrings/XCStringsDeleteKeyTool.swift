import MCP
import XCMCPCore
import Foundation

public struct XCStringsDeleteKeyTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_delete_key",
            description: "Delete a key entirely",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("The key to delete"),
                    ]),
                ]),
                "required": .array([.string("file"), .string("key")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let key = try arguments.getRequiredString("key")

        return try await pathUtility.withParser(at: filePath) { parser, _ in
            try await parser.deleteKey(key)

            return CallTool.Result.text("Key deleted successfully")
        }
    }
}
