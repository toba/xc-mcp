import MCP
import XCMCPCore
import Foundation

public struct SetTestPlanSkippedTestsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_test_plan_skipped_tests",
            description:
                "Add or remove entries in a .xctestplan's skippedTests exclusion list (\"run everything EXCEPT these\"). "
                + "Unlike skippedTags, this catches XCTest classes/methods which have no tags. "
                + "Can apply to plan-level defaults or a specific test target. "
                + "Handles both shapes Xcode writes: the flat array of identifiers, and the "
                + "nested dictionary of 'suites' and 'xctestClasses'. Only the named entry "
                + "changes, and the reply states the entry count before and after.",
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
                                + "(e.g. 'XMLDecoderPerformanceTests'), a specific method "
                                + "(e.g. 'XMLDecoderPerformanceTests/testDecode()'), or a "
                                + "nested suite path (e.g. 'ParentSuite/ChildSuite').",
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

    /// The change the caller asks for.
    private enum Action: String {
        case add
        case remove

        /// The past-tense verb that opens the reply.
        var verb: String {
            switch self {
                case .add: "Added"
                case .remove: "Removed"
            }
        }
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let testPlanPath = try arguments.getRequiredString("test_plan_path")
        let tests = arguments.getStringArray("tests")
        let targetName = arguments.getString("target_name")

        guard let action = Action(rawValue: arguments.getString("action") ?? "add") else {
            throw MCPError.invalidParams("action must be 'add' or 'remove'")
        }
        guard !tests.isEmpty else { throw MCPError.invalidParams("tests array must not be empty") }
        guard tests.allSatisfy({ !$0.isEmpty }) else {
            throw MCPError.invalidParams("tests must not contain an empty identifier")
        }

        let resolvedPath = try pathUtility.resolvePath(from: testPlanPath)

        do {
            var json = try TestPlanFile.read(from: resolvedPath)

            let outcome = try TestPlanFile.mutateScope(&json, targetName: targetName) { scope in
                Self.apply(action, tests: tests, in: &scope)
            }

            try TestPlanFile.write(json, to: resolvedPath)

            let scope = targetName.map { "target '\($0)'" } ?? "plan-level defaults"
            let testList = tests.map { "'\($0)'" }.joined(separator: ", ")
            return CallTool.Result.text(
                "\(action.verb) \(testList) in \(scope)\(Self.report(outcome))")
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Builds the part of the reply that describes what the plan now holds.
    ///
    /// The reply always states the entry count before the change and after it. That count lets the
    /// caller see at once when a change removed more than it named.
    private static func report(_ outcome: TestPlanSkipList.Outcome) -> String {
        var parts: [String] = []

        switch outcome.shape {
            case .absent: parts.append("no skipped tests remaining")
            case let .flat(names): parts.append("skipped tests: \(names.joined(separator: ", "))")
            case let .structured(suiteCount, classCount):
                var scopeCounts: [String] = []
                if suiteCount > 0 { scopeCounts.append("\(suiteCount) suite(s)") }
                if classCount > 0 { scopeCounts.append("\(classCount) XCTest class(es)") }
                parts.append("skipped tests in \(scopeCounts.joined(separator: " and "))")
        }

        parts.append("entries: \(outcome.entriesBefore) → \(outcome.entriesAfter)")

        if !outcome.unmatched.isEmpty {
            let list = outcome.unmatched.map { "'\($0)'" }.joined(separator: ", ")
            parts.append("no matching entry for \(list)")
        }
        if !outcome.alreadyPresent.isEmpty {
            let list = outcome.alreadyPresent.map { "'\($0)'" }.joined(separator: ", ")
            parts.append("already skipped: \(list)")
        }

        return " — " + parts.joined(separator: "; ")
    }

    /// Applies an action to the `skippedTests` value of one scope and writes the result back.
    ///
    /// The key drops when the change leaves no entries, because Xcode omits an empty list.
    private static func apply(
        _ action: Action,
        tests: [String],
        in scope: inout [String: AnyValue],
    ) -> TestPlanSkipList.Outcome {
        let value = scope["skippedTests"]
        let outcome =
            switch action {
                case .add: TestPlanSkipList.adding(tests, to: value)
                case .remove: TestPlanSkipList.removing(tests, from: value)
            }

        if let newValue = outcome.value {
            scope["skippedTests"] = newValue
        } else {
            scope.removeValue(forKey: "skippedTests")
        }
        return outcome
    }
}
