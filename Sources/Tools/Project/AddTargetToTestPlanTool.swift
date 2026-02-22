import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

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
                            "Path to the .xcodeproj file (for target UUID lookup)"
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
                ]),
                "required": .array([
                    .string("project_path"), .string("test_plan_path"), .string("target_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(testPlanPath) = arguments["test_plan_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, test_plan_path, and target_name are required"
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
                    content: [.text("Target '\(targetName)' not found in project")]
                )
            }

            var json = try TestPlanFile.read(from: resolvedTestPlanPath)
            var testTargets = json["testTargets"] as? [[String: Any]] ?? []

            // Check for duplicate
            let existingNames = TestPlanFile.targetNames(from: json)
            if existingNames.contains(targetName) {
                return CallTool.Result(
                    content: [
                        .text(
                            "Target '\(targetName)' is already in the test plan"
                        )
                    ]
                )
            }

            let containerPath = "container:\(projectURL.lastPathComponent)"
            let entry: [String: Any] = [
                "target": [
                    "containerPath": containerPath,
                    "identifier": target.uuid,
                    "name": targetName,
                ] as [String: Any]
            ]
            testTargets.append(entry)
            json["testTargets"] = testTargets

            try TestPlanFile.write(json, to: resolvedTestPlanPath)

            return CallTool.Result(
                content: [
                    .text(
                        "Added target '\(targetName)' to test plan at \(resolvedTestPlanPath)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add target to test plan: \(error.localizedDescription)"
            )
        }
    }
}
