import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddTestPlanToSchemeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_test_plan_to_scheme",
            description: "Add a test plan reference to an existing scheme's TestAction",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "scheme_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the existing scheme"),
                    ]),
                    "test_plan_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xctestplan file"),
                    ]),
                    "is_default": .object([
                        "type": .string("boolean"),
                        "description": .string("Mark this as the default test plan"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("scheme_name"), .string("test_plan_path"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(schemeName) = arguments["scheme_name"],
              case let .string(testPlanPath) = arguments["test_plan_path"]
        else {
            throw MCPError.invalidParams(
                "project_path, scheme_name, and test_plan_path are required",
            )
        }

        let isDefault: Bool
        if case let .bool(value) = arguments["is_default"] {
            isDefault = value
        } else {
            isDefault = false
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let resolvedTestPlanPath = try pathUtility.resolvePath(from: testPlanPath)

        guard FileManager.default.fileExists(atPath: resolvedTestPlanPath) else {
            return CallTool.Result(
                content: [.text("Test plan file not found at \(resolvedTestPlanPath)")],
            )
        }

        guard
            let schemePath = SchemePathResolver.findScheme(
                named: schemeName, in: resolvedProjectPath,
            )
        else {
            return CallTool.Result(
                content: [
                    .text("Scheme '\(schemeName)' not found in project"),
                ],
            )
        }

        do {
            let scheme = try XCScheme(pathString: schemePath)

            let reference = SchemePathResolver.containerReference(
                for: resolvedTestPlanPath, relativeTo: resolvedProjectPath,
            )

            // Check for duplicate
            if let existingPlans = scheme.testAction?.testPlans,
               existingPlans.contains(where: { $0.reference == reference })
            {
                return CallTool.Result(
                    content: [
                        .text(
                            "Test plan is already referenced in scheme '\(schemeName)'",
                        ),
                    ],
                )
            }

            let testPlanRef = XCScheme.TestPlanReference(
                reference: reference,
                default: isDefault,
            )

            if let testAction = scheme.testAction {
                var plans = testAction.testPlans ?? []
                if isDefault {
                    plans = plans.map {
                        XCScheme.TestPlanReference(reference: $0.reference, default: false)
                    }
                }
                plans.append(testPlanRef)
                testAction.testPlans = plans
            } else {
                // Create a minimal TestAction with the test plan
                let testAction = XCScheme.TestAction(
                    buildConfiguration: scheme.launchAction?.buildConfiguration ?? "Debug",
                    macroExpansion: nil,
                    testPlans: [testPlanRef],
                )
                scheme.testAction = testAction
            }

            try scheme.write(path: Path(schemePath), override: true)

            return CallTool.Result(
                content: [
                    .text(
                        "Added test plan to scheme '\(schemeName)'\(isDefault ? " (set as default)" : "")",
                    ),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add test plan to scheme: \(error.localizedDescription)",
            )
        }
    }
}
