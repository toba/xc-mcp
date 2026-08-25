import MCP
import XCMCPCore

public struct XCStringsListStaleTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_list_stale",
            description:
                "List keys with extractionState 'stale' (potentially unused) in an xcstrings file",
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
            let staleKeys = try await parser.listStaleKeys()

            let result = StaleKeysResult(file: filePath, staleKeys: staleKeys)
            let json = try encodePrettyJSON(result)

            return CallTool.Result.text(json)
        }
    }
}
