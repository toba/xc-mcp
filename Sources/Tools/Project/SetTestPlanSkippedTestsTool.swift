import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanSkippedTestsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "set_test_plan_skipped_tests",
            description:
            "Add or remove entries in a .xctestplan's skippedTests exclusion list (\"run everything EXCEPT these\"). "
                + "Unlike skippedTags, this catches XCTest classes/methods which have no tags. "
                + "Can apply to plan-level defaults or a specific test target.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "tests": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Test identifiers to add or remove — a class/suite name "
                                + "(e.g. 'XMLDecoderPerformanceTests') or a specific method "
                                + "(e.g. 'XMLDecoderPerformanceTests/testDecode()').",
                        ),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("add"), .string("remove")]),
                        "description": .string(
                            "Whether to add or remove the tests. Defaults to 'add'.",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of a specific test target. If omitted, applies to plan-level defaultOptions.",
                        ),
                    ]),
                ]),
                "required": .array([.string("test_plan_path"), .string("tests")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let testPlanPath = try arguments.getRequiredString("test_plan_path")
        let tests = arguments.getStringArray("tests")
        let action = arguments.getString("action") ?? "add"
        let targetName = arguments.getString("target_name")

        guard action == "add" || action == "remove" else {
            throw MCPError.invalidParams("action must be 'add' or 'remove'")
        }
        guard !tests.isEmpty else {
            throw MCPError.invalidParams("tests array must not be empty")
        }

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            let resultTests: [String]
            if let targetName {
                resultTests = try applyToTarget(
                    &json, targetName: targetName, tests: tests, action: action,
                )
            } else {
                resultTests = applyToDefaults(&json, tests: tests, action: action)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let verb = action == "add" ? "Added" : "Removed"
            let testList = tests.map { "'\($0)'" }.joined(separator: ", ")
            let remaining =
                resultTests.isEmpty
                    ? " (no skipped tests remaining)"
                    : " — skipped tests: \(resultTests.joined(separator: ", "))"
            return CallTool.Result(
                content: [
                    .text(
                        text: "\(verb) \(testList) in \(scope)\(remaining)",
                        annotations: nil,
                        _meta: nil,
                    ),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to update test plan skipped tests: \(error.localizedDescription)",
            )
        }
    }

    /// Adds or removes tests from an existing list, preserving insertion order.
    private func applyTestChanges(
        existing: [String],
        tests: [String],
        action: String,
    ) -> [String] {
        if action == "add" {
            let existingSet = Set(existing)
            return existing + tests.filter { !existingSet.contains($0) }
        } else {
            let removeSet = Set(tests)
            return existing.filter { !removeSet.contains($0) }
        }
    }

    /// Applies changes to plan-level `defaultOptions.skippedTests`.
    private func applyToDefaults(
        _ json: inout [String: Any],
        tests: [String],
        action: String,
    ) -> [String] {
        var defaults = json["defaultOptions"] as? [String: Any] ?? [:]
        let existing = defaults["skippedTests"] as? [String] ?? []

        let result = applyTestChanges(existing: existing, tests: tests, action: action)

        if result.isEmpty {
            defaults.removeValue(forKey: "skippedTests")
        } else {
            defaults["skippedTests"] = result
        }

        json["defaultOptions"] = defaults
        return result
    }

    /// Applies changes to a specific target's `skippedTests`.
    private func applyToTarget(
        _ json: inout [String: Any],
        targetName: String,
        tests: [String],
        action: String,
    ) throws(MCPError) -> [String] {
        guard var testTargets = json["testTargets"] as? [[String: Any]] else {
            throw MCPError.invalidParams("Test plan has no test targets")
        }

        guard
            let index = testTargets.firstIndex(where: {
                ($0["target"] as? [String: Any])?["name"] as? String == targetName
            })
        else {
            throw MCPError.invalidParams("Target '\(targetName)' not found in test plan")
        }

        var entry = testTargets[index]
        let existing = entry["skippedTests"] as? [String] ?? []

        let result = applyTestChanges(existing: existing, tests: tests, action: action)

        if result.isEmpty {
            entry.removeValue(forKey: "skippedTests")
        } else {
            entry["skippedTests"] = result
        }

        testTargets[index] = entry
        json["testTargets"] = testTargets
        return result
    }
}
