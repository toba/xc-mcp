import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanSkippedTagsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_test_plan_skipped_tags",
            description:
                "Add or remove skipped test tags in a .xctestplan file. Can apply to plan-level defaults or a specific test target.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Tag strings to add or remove (e.g., '.api', '.testSuiteFile')",
                        ),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("add"), .string("remove")]),
                        "description": .string(
                            "Whether to add or remove the tags. Defaults to 'add'.",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of a specific test target. If omitted, applies to plan-level defaultOptions.",
                        ),
                    ]),
                ]),
                "required": .array([.string("test_plan_path"), .string("tags")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let testPlanPath = try arguments.getRequiredString("test_plan_path")
        let tags = arguments.getStringArray("tags")
        let action = arguments.getString("action") ?? "add"
        let targetName = arguments.getString("target_name")

        guard action == "add" || action == "remove" else {
            throw MCPError.invalidParams("action must be 'add' or 'remove'")
        }
        guard !tags.isEmpty else { throw MCPError.invalidParams("tags array must not be empty") }

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            let resultTags = try TestPlanFile.mutateScope(&json, targetName: targetName) { scope in
                Self.applySkippedTags(to: &scope, tags: tags, action: action)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let verb = action == "add" ? "Added" : "Removed"
            let tagList = tags.map { "'\($0)'" }.joined(separator: ", ")
            let remaining = resultTags.isEmpty
                ? " (no skipped tags remaining)"
                : " — skipped tags: \(resultTags.joined(separator: ", "))"
            return CallTool.Result.text("\(verb) \(tagList) in \(scope)\(remaining)")
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Adds or removes tags from an existing tag list, preserving insertion order.
    private static func applyTagChanges(
        existing: [String],
        tags: [String],
        action: String,
    ) -> [String] {
        if action == "add" {
            let existingSet = Set(existing)
            return existing + tags.filter { !existingSet.contains($0) }
        } else {
            let removeSet = Set(tags)
            return existing.filter { !removeSet.contains($0) }
        }
    }

    /// Rewrites the `skippedTags` block of one scope and reports the tags it now holds.
    ///
    /// The key drops when no tag remains, because Xcode omits an empty block.
    private static func applySkippedTags(
        to scope: inout [String: AnyValue],
        tags: [String],
        action: String,
    ) -> [String] {
        var skipped = scope["skippedTags"]?.dictionaryValue ?? [:]
        let existing = skipped["tags"]?.stringArrayValue ?? []

        let result = applyTagChanges(existing: existing, tags: tags, action: action)

        if result.isEmpty {
            scope.removeValue(forKey: "skippedTags")
        } else {
            skipped["tags"] = .strings(result)
            // Preserve existing "mode"; default to "or" so the block uses OR semantics (absence
            // means AND, which silently no-ops in practice).
            if skipped["mode"] == nil { skipped["mode"] = "or" }
            scope["skippedTags"] = .dictionary(skipped)
        }

        return result
    }
}
