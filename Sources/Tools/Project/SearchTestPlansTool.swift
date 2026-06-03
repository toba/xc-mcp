import MCP
import XCMCPCore
import Foundation

/// Substring search across all `.xctestplan` files under a project directory.
///
/// Closes the gap left by the operation-specific test-plan tools (add/remove/skip/etc.)
/// when an agent needs to sweep test-plan JSON contents for an arbitrary string —
/// e.g. confirming a bundle-ID rename did not leave references behind. Returns the
/// matching JSON paths and values per file, so a single tool call replaces N Reads.
public struct SearchTestPlansTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "search_test_plans",
            description:
            "Search every `.xctestplan` file under a project for a substring, returning the JSON paths and matching values per file. Use for rename/refactor sweeps (e.g. confirming no test plan still references an old bundle ID, scheme name, or target name) when the per-operation test-plan tools don't help. Matches against both keys and string values; numeric/boolean leaves are stringified. Single tool call replaces reading every `.xctestplan` individually.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (search root is the parent directory).",
                        ),
                    ]),
                    "query": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Substring to search for. Matched against both JSON keys and stringified leaf values.",
                        ),
                    ]),
                    "case_sensitive": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether the substring match is case-sensitive. Defaults to true.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("query")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }
        guard case let .string(query) = arguments["query"], !query.isEmpty else {
            throw MCPError.invalidParams("query is required and must be non-empty")
        }
        var caseSensitive = true
        if case let .bool(value) = arguments["case_sensitive"] {
            caseSensitive = value
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let searchRoot = URL(fileURLWithPath: resolvedProjectPath)
            .deletingLastPathComponent().path

        let testPlans = TestPlanFile.findFiles(under: searchRoot)

        if testPlans.isEmpty {
            return CallTool.Result(content: [.text(
                text: "No .xctestplan files found under \(searchRoot)",
                annotations: nil,
                _meta: nil,
            )])
        }

        let needle = caseSensitive ? query : query.lowercased()

        struct FileMatches {
            let path: String
            var hits: [(jsonPath: String, value: String)]
        }

        var matches: [FileMatches] = []
        for plan in testPlans {
            var fileHits: [(jsonPath: String, value: String)] = []
            walk(
                json: plan.json,
                jsonPath: "$",
                needle: needle,
                caseSensitive: caseSensitive,
                hits: &fileHits,
            )
            if !fileHits.isEmpty {
                matches.append(FileMatches(path: plan.path, hits: fileHits))
            }
        }

        if matches.isEmpty {
            return CallTool.Result(content: [.text(
                text: "Searched \(testPlans.count) test plan(s) under \(searchRoot); no matches for \"\(query)\".",
                annotations: nil,
                _meta: nil,
            )])
        }

        var lines = [
            "Searched \(testPlans.count) test plan(s); \(matches.count) file(s) matched \"\(query)\":\n",
        ]
        for file in matches {
            lines.append("  \(file.path)")
            for hit in file.hits {
                lines.append("    \(hit.jsonPath) = \(hit.value)")
            }
            lines.append("")
        }

        return CallTool.Result(content: [.text(
            text: lines.joined(separator: "\n"),
            annotations: nil,
            _meta: nil,
        )])
    }

    private func walk(
        json: Any,
        jsonPath: String,
        needle: String,
        caseSensitive: Bool,
        hits: inout [(jsonPath: String, value: String)],
    ) {
        switch json {
            case let dict as [String: Any]:
                for (key, value) in dict {
                    let childPath = "\(jsonPath).\(key)"
                    let haystackKey = caseSensitive ? key : key.lowercased()
                    if haystackKey.contains(needle) {
                        hits.append((jsonPath: childPath, value: "<key match>"))
                    }
                    walk(
                        json: value,
                        jsonPath: childPath,
                        needle: needle,
                        caseSensitive: caseSensitive,
                        hits: &hits,
                    )
                }
            case let array as [Any]:
                for (index, value) in array.enumerated() {
                    walk(
                        json: value,
                        jsonPath: "\(jsonPath)[\(index)]",
                        needle: needle,
                        caseSensitive: caseSensitive,
                        hits: &hits,
                    )
                }
            default:
                let stringValue = String(describing: json)
                let haystack = caseSensitive ? stringValue : stringValue.lowercased()
                if haystack.contains(needle) {
                    hits.append((jsonPath: jsonPath, value: stringValue))
                }
        }
    }
}
