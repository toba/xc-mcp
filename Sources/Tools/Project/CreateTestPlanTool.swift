import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct CreateTestPlanTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "create_test_plan",
            description: "Create a .xctestplan file for the given project and test targets",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Test plan name (without .xctestplan extension)"),
                    ]),
                    "output_directory": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory to write the test plan file (defaults to project parent directory)"
                        ),
                    ]),
                    "test_targets": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Array of test target names to include"),
                    ]),
                    "code_coverage_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable code coverage (defaults to false)"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(name) = arguments["name"]
        else {
            throw MCPError.invalidParams("project_path and name are required")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let projectURL = URL(fileURLWithPath: resolvedProjectPath)

        // Determine output directory
        let outputDir: String
        if case let .string(dir) = arguments["output_directory"] {
            outputDir = try pathUtility.resolvePath(from: dir)
        } else {
            outputDir = projectURL.deletingLastPathComponent().path
        }

        let outputPath = "\(outputDir)/\(name).xctestplan"

        // Check if file already exists
        if FileManager.default.fileExists(atPath: outputPath) {
            return CallTool.Result(
                content: [.text("Test plan '\(name).xctestplan' already exists at \(outputPath)")]
            )
        }

        // Parse test target names
        var targetNames: [String] = []
        if case let .array(targets) = arguments["test_targets"] {
            for target in targets {
                if case let .string(targetName) = target {
                    targetNames.append(targetName)
                }
            }
        }

        let codeCoverageEnabled: Bool
        if case let .bool(enabled) = arguments["code_coverage_enabled"] {
            codeCoverageEnabled = enabled
        } else {
            codeCoverageEnabled = false
        }

        do {
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Build test target entries
            var testTargetEntries: [[String: Any]] = []
            for targetName in targetNames {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text("Test target '\(targetName)' not found in project")
                        ]
                    )
                }

                let containerPath =
                    "container:\(projectURL.lastPathComponent)"
                let entry: [String: Any] = [
                    "target": [
                        "containerPath": containerPath,
                        "identifier": target.uuid,
                        "name": targetName,
                    ] as [String: Any]
                ]
                testTargetEntries.append(entry)
            }

            // Build test plan JSON
            var defaultOptions: [String: Any] = [:]
            if codeCoverageEnabled {
                defaultOptions["codeCoverageEnabled"] = true
            }

            let testPlanJSON: [String: Any] = [
                "configurations": [
                    [
                        "id": UUID().uuidString,
                        "name": "Test Scheme Action",
                        "options": [:] as [String: Any],
                    ] as [String: Any]
                ],
                "defaultOptions": defaultOptions,
                "testTargets": testTargetEntries,
                "version": 1,
            ]

            try TestPlanFile.write(testPlanJSON, to: outputPath)

            var summary = "Created test plan '\(name).xctestplan' at \(outputPath)"
            if !targetNames.isEmpty {
                summary += "\nTest targets: \(targetNames.joined(separator: ", "))"
            }

            return CallTool.Result(content: [.text(summary)])
        } catch {
            throw MCPError.internalError(
                "Failed to create test plan: \(error.localizedDescription)"
            )
        }
    }
}
