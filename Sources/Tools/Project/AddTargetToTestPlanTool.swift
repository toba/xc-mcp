import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddTargetToTestPlanTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(testPlanPath) = arguments["test_plan_path"],
              case let .string(targetName) = arguments["target_name"]
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

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                return CallTool.Result(
                    content: [.text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            var testTargets = json["testTargets"] as? [[String: Any]] ?? []

            // Check for duplicate
            let existingNames = TestPlanFile.targetNames(from: json)
            if existingNames.contains(targetName) {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Target '\(targetName)' is already in the test plan",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            let containerPath = TestPlanFile.containerPath(for: projectURL)
            var entry: [String: Any] = [
                "target": [
                    "containerPath": containerPath,
                    "identifier": target.uuid,
                    "name": targetName,
                ] as [String: Any],
            ]

            let selectedTests = Self.buildSelectedTests(from: arguments)
            if !selectedTests.isEmpty {
                entry["selectedTests"] = selectedTests
            }

            testTargets.append(entry)
            json["testTargets"] = testTargets

            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            return CallTool.Result(
                content: [
                    .text(text:
                        "Added target '\(targetName)' to test plan at \(resolvedTestPlanPath)",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add target to test plan: \(error.localizedDescription)",
            )
        }
    }

    /// Builds a `selectedTests` dictionary from `xctest_classes` and `suites` parameters.
    ///
    /// Returns an empty dictionary when neither parameter is provided.
    private static func buildSelectedTests(from arguments: [String: Value]) -> [String: Any] {
        var selected: [String: Any] = [:]

        if case let .array(classes) = arguments["xctest_classes"] {
            var xctestClasses: [[String: Any]] = []
            for item in classes {
                guard case let .object(obj) = item,
                      case let .string(name) = obj["name"]
                else { continue }
                var classEntry: [String: Any] = ["name": name]
                if case let .array(methods) = obj["xctest_methods"] {
                    let methodNames = methods.compactMap { value -> String? in
                        guard case let .string(s) = value else { return nil }
                        return s
                    }
                    if !methodNames.isEmpty {
                        classEntry["xctestMethods"] = methodNames
                    }
                }
                xctestClasses.append(classEntry)
            }
            if !xctestClasses.isEmpty {
                selected["xctestClasses"] = xctestClasses
            }
        }

        if case let .array(suiteValues) = arguments["suites"] {
            var suites: [[String: Any]] = []
            for item in suiteValues {
                guard case let .object(obj) = item,
                      case let .string(name) = obj["name"]
                else { continue }
                var suiteEntry: [String: Any] = ["name": name]
                if case let .array(functions) = obj["test_functions"] {
                    let funcNames = functions.compactMap { value -> String? in
                        guard case let .string(s) = value else { return nil }
                        return s
                    }
                    if !funcNames.isEmpty {
                        suiteEntry["testFunctions"] = funcNames
                    }
                }
                suites.append(suiteEntry)
            }
            if !suites.isEmpty {
                selected["suites"] = suites
            }
        }

        return selected
    }
}
