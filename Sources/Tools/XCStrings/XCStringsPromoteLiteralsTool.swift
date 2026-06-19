import MCP
import XCMCPCore

/// Promotes hand-typed localizable string literals to reusable manual String Catalog keys.
///
/// This is the mechanical half of the "deduplicate localized literals" workflow: the caller (which
/// has already identified the literals worth centralizing) hands the tool one or more values, and
/// it adds `extractionState: manual` source-language entries to the `.xcstrings`, deriving a
/// `SCREAMING_SNAKE` key for each and reporting the camelCased Swift symbol Xcode 26 will generate
/// (e.g. `NONE_SELECTED` → `Text(.noneSelected)`). Existing keys holding the same value are reused
/// rather than duplicated.
public struct XCStringsPromoteLiteralsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "xcstrings_promote_literals",
            description:
                "Promote hand-typed localizable string literals to reusable manual String Catalog keys. "
                + "For each literal, adds an extractionState=manual source-language entry to the "
                + ".xcstrings, derives a SCREAMING_SNAKE key (unless one is given), and returns the "
                + "camelCased Swift symbol Xcode generates (e.g. NONE_SELECTED -> .noneSelected) so "
                + "you can rewrite call sites like Button(\"Cancel\") to Button(.cancel). Reuses an "
                + "existing key when one already holds the same value; reports a collision when a "
                + "target key exists with a different value. Parameterized values are supported: "
                + "pass the format string (e.g. \"Add %1$(ordinal)@ citation\") and the result "
                + "includes the generated method signature (addCitationToGroup(ordinal: String)); "
                + "supply an explicit key for these. Does not edit Swift sources.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcstrings file"),
                    ]),
                    "literals": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "value": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "The source-language literal text, e.g. \"Cancel\". May "
                                            + "include format placeholders for parameterized "
                                            + "strings, e.g. \"Add %1$(ordinal)@ citation\".",
                                    ),
                                ]),
                                "key": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Optional explicit SCREAMING_SNAKE key. Derived from the "
                                            + "value when omitted.",
                                    ),
                                ]),
                                "comment": .object([
                                    "type": .string("string"),
                                    "description": .string(
                                        "Optional developer comment stored on the entry.",
                                    ),
                                ]),
                            ]),
                            "required": .array([.string("value")]),
                        ]),
                        "description": .string(
                            "Literals to promote. Each needs a 'value'; 'key' and 'comment' are "
                                + "optional.",
                        ),
                    ]),
                ]),
                "required": .array([.string("file"), .string("literals")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let filePath = try arguments.getRequiredString("file")
        let requests = try Self.parseRequests(arguments)

        guard !requests.isEmpty else {
            throw MCPError.invalidParams("literals array is required and cannot be empty")
        }

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)
            let promoted = try await parser.promoteLiterals(requests)
            let result = PromoteLiteralsResult(file: resolvedPath, promoted: promoted)
            let json = try encodePrettyJSON(result)
            return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }

    private static func parseRequests(
        _ arguments: [String: Value],
    ) throws -> [PromoteLiteralRequest] {
        guard case let .array(items) = arguments["literals"] else {
            throw MCPError.invalidParams("literals must be an array")
        }

        return try items.map { item in
            guard case let .object(obj) = item, case let .string(value) = obj["value"] else {
                throw MCPError.invalidParams("Each literal must have a 'value' string")
            }
            var key: String?
            if case let .string(k) = obj["key"], !k.isEmpty { key = k }
            var comment: String?
            if case let .string(c) = obj["comment"], !c.isEmpty { comment = c }
            return PromoteLiteralRequest(value: value, key: key, comment: comment)
        }
    }
}
