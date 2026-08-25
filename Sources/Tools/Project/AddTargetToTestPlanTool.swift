import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddTargetToTestPlanTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_target_to_test_plan",
            description: "Add a test target to an existing .xctestplan file",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (for target UUID lookup)",
                        ),
                    ]),
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the test target to add"),
                    ]),
                    "xctest_classes": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object([
                                    "type": .string("string"),
                                    "description": .string("XCTest class name"),
                                ]),
                                "xctest_methods": .object([
                                    "type": .string("array"),
                                    "items": .object(["type": .string("string")]),
                                    "description": .string(
                                        "Specific XCTest methods to include (e.g. 'testDecodeSampleItems()'). "
                                            + "Omit to include all methods.",
                                    ),
                                ]),
                            ]),
                            "required": .array([.string("name")]),
                        ]),
                        "description": .string(
                            "XCTest classes to include in selectedTests (e.g. 'XMLDecoderPerformanceTests'). "
                                + "Omit to include the entire target.",
                        ),
                    ]),
                    "suites": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object([
                                    "type": .string("string"),
                                    "description": .string("Swift Testing suite name"),
                                ]),
                                "test_functions": .object([
                                    "type": .string("array"),
                                    "items": .object(["type": .string("string")]),
                                    "description": .string(
                                        "Specific test functions to include (e.g. 'fetchKeys()'). "
                                            + "Omit to include all functions in the suite.",
                                    ),
                                ]),
                            ]),
                            "required": .array([.string("name")]),
                        ]),
                        "description": .string(
                            "Swift Testing suites to include in selectedTests. "
                                + "Omit to include the entire target.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("test_plan_path"), .string("target_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let testPlanPath = arguments.getString("test_plan_path"),
              let targetName = arguments.getString("target_name")
        else {
            throw MCPError.invalidParams(
                "project_path, test_plan_path, and target_name are required",
            )
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)
        let projectURL = URL(fileURLWithPath: resolvedProjectPath)

        do {
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            var testTargets = TestPlanFile.testTargets(in: json)

            // Check for duplicate
            let existingNames = TestPlanFile.targetNames(from: json)

            if existingNames.contains(targetName) {
                return CallTool.Result.text("Target '\(targetName)' is already in the test plan")
            }

            let containerPath = TestPlanFile.containerPath(for: projectURL)
            var entry: [String: AnyValue] = [
                "target": [
                    "containerPath": .string(containerPath),
                    "identifier": .string(target.uuid),
                    "name": .string(targetName),
                ]
            ]

            let selectedTests = Self.buildSelectedTests(from: arguments)
            if !selectedTests.isEmpty { entry["selectedTests"] = .dictionary(selectedTests) }

            testTargets.append(entry)
            json["testTargets"] = .dictionaries(testTargets)

            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            return CallTool.Result.text(
                "Added target '\(targetName)' to test plan at \(resolvedTestPlanPath)")
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Builds a `selectedTests` dictionary from `xctest_classes` and `suites` parameters.
    ///
    /// Returns an empty dictionary when neither parameter is provided.
    private static func buildSelectedTests(from arguments: [String: Value]) -> [String: AnyValue] {
        var selected: [String: AnyValue] = [:]

        let xctestClasses = namedEntries(
            in: arguments, key: "xctest_classes", childKey: "xctest_methods",
            childJSONKey: "xctestMethods",
        )
        if !xctestClasses.isEmpty { selected["xctestClasses"] = .array(xctestClasses) }

        let suites = namedEntries(
            in: arguments, key: "suites", childKey: "test_functions",
            childJSONKey: "testFunctions",
        )
        if !suites.isEmpty { selected["suites"] = .array(suites) }

        return selected
    }

    /// Reads an array of `{ name, <childKey>: [String] }` objects into test-plan JSON entries.
    ///
    /// - Parameters:
    ///   - arguments: The tool arguments dictionary.
    ///   - key: The argument key holding the array of objects.
    ///   - childKey: The key each object uses for its nested string array.
    ///   - childJSONKey: The key the test-plan JSON uses for that same array.
    /// - Returns: One entry per object that carries a name. An object without one is skipped.
    private static func namedEntries(
        in arguments: [String: Value],
        key: String,
        childKey: String,
        childJSONKey: String,
    ) -> [AnyValue] {
        guard case let .array(items) = arguments[key] else { return [] }

        var entries: [AnyValue] = []
        entries.reserveCapacity(items.count)

        for item in items {
            guard case let .object(obj) = item, let name = obj.getString("name") else { continue }
            var entry: [String: AnyValue] = ["name": .string(name)]
            let children = obj.getStringArray(childKey)
            if !children.isEmpty { entry[childJSONKey] = .strings(children) }
            entries.append(.dictionary(entry))
        }
        return entries
    }
}
