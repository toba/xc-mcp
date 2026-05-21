import MCP
import XCMCPCore

/// State-aware untranslated check across one file × N languages.
///
/// Ported from Ryu0118/xcstrings-crud PR #33 (`feature/check-untranslated-hooks`).
/// Returns structured `UntranslatedIssue` rows with a `reason` enum so callers
/// can distinguish missing keys from empty values, `needs_review` state,
/// partial plural/device variation coverage, etc. — gaps that the existing
/// `xcstrings_list_untranslated` tool silently misses.
public struct XCStringsCheckUntranslatedTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "xcstrings_check_untranslated",
            description:
                "State-aware untranslated check. Unlike xcstrings_list_untranslated (which only checks presence), this inspects stringUnit.state, empty values, and plural/device variation completeness. Returns structured issues with a `reason` enum: missing_localization, empty_value, state_not_translated, missing_variation_string_unit, etc. Pass `languages` to restrict the check, or omit to scan every language in the file.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file": .object([
                        "type": .string("string"),
                        "description": .string("Path to the xcstrings file"),
                    ]),
                    "languages": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Language codes to check. Defaults to all languages in the file (including source).",
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
        let languagesArg = arguments.getStringArray("languages")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: filePath)
            let parser = XCStringsParser(path: resolvedPath)

            let languages = languagesArg.isEmpty
                ? try await parser.listLanguages()
                : languagesArg

            let issues = try await parser.checkUntranslated(languages: languages)
            let result = UntranslatedCheckResult(file: resolvedPath, issues: issues)

            let json = try encodePrettyJSON(result, fallback: "{}")
            return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
        } catch let error as XCStringsError {
            throw error.toMCPError()
        } catch let error as PathError {
            throw MCPError.invalidParams(error.localizedDescription)
        }
    }
}
