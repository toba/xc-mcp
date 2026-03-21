import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanSkippedTagsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
        guard !tags.isEmpty else {
            throw MCPError.invalidParams("tags array must not be empty")
        }

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            let resultTags: [String]
            if let targetName {
                resultTags = try applyToTarget(
                    &json, targetName: targetName, tags: tags, action: action,
                )
            } else {
                resultTags = applyToDefaults(&json, tags: tags, action: action)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let verb = action == "add" ? "Added" : "Removed"
            let tagList = tags.map { "'\($0)'" }.joined(separator: ", ")
            let remaining = resultTags.isEmpty
                ? " (no skipped tags remaining)"
                : " — skipped tags: \(resultTags.joined(separator: ", "))"
            return CallTool.Result(
                content: [
                    .text("\(verb) \(tagList) in \(scope)\(remaining)"),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to update test plan skipped tags: \(error.localizedDescription)",
            )
        }
    }

    /// Adds or removes tags from an existing tag list, preserving insertion order.
    private func applyTagChanges(
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

    /// Applies tag changes to plan-level `defaultOptions.skippedTags`.
    private func applyToDefaults(
        _ json: inout [String: Any],
        tags: [String],
        action: String,
    ) -> [String] {
        var defaults = json["defaultOptions"] as? [String: Any] ?? [:]
        var skipped = defaults["skippedTags"] as? [String: Any] ?? [:]
        let existing = skipped["tags"] as? [String] ?? []

        let result = applyTagChanges(existing: existing, tags: tags, action: action)

        if result.isEmpty {
            defaults.removeValue(forKey: "skippedTags")
        } else {
            skipped["tags"] = result
            // Plan-level uses "mode" key
            if skipped["mode"] == nil {
                skipped["mode"] = "or"
            }
            defaults["skippedTags"] = skipped
        }

        json["defaultOptions"] = defaults
        return result
    }

    /// Applies tag changes to a specific target's `skippedTags`.
    private func applyToTarget(
        _ json: inout [String: Any],
        targetName: String,
        tags: [String],
        action: String,
    ) throws(MCPError) -> [String] {
        guard var testTargets = json["testTargets"] as? [[String: Any]] else {
            throw MCPError.invalidParams("Test plan has no test targets")
        }

        guard let index = testTargets.firstIndex(where: {
            ($0["target"] as? [String: Any])?["name"] as? String == targetName
        }) else {
            throw MCPError.invalidParams("Target '\(targetName)' not found in test plan")
        }

        var entry = testTargets[index]
        var skipped = entry["skippedTags"] as? [String: Any] ?? [:]
        let existing = skipped["tags"] as? [String] ?? []

        let result = applyTagChanges(existing: existing, tags: tags, action: action)

        if result.isEmpty {
            entry.removeValue(forKey: "skippedTags")
        } else {
            // Per-target: no "mode" key (Xcode omits it)
            skipped["tags"] = result
            skipped.removeValue(forKey: "mode")
            entry["skippedTags"] = skipped
        }

        testTargets[index] = entry
        json["testTargets"] = testTargets
        return result
    }
}
