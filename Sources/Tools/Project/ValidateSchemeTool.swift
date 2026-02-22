import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ValidateSchemeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "validate_scheme",
            description:
            "Validate that an Xcode scheme's target references, test plans, and configurations are valid",
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
                        "description": .string("Name of the scheme to validate"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("scheme_name")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(schemeName) = arguments["scheme_name"]
        else {
            throw MCPError.invalidParams("project_path and scheme_name are required")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let projectURL = URL(fileURLWithPath: resolvedProjectPath)

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
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let targetNames = Set(xcodeproj.pbxproj.nativeTargets.map(\.name))
            let configNames = Set(
                xcodeproj.pbxproj.buildConfigurations.map(\.name),
            )

            var issues: [String] = []

            // Check build action target references
            if let buildAction = scheme.buildAction {
                for entry in buildAction.buildActionEntries {
                    let name = entry.buildableReference.blueprintName
                    if !targetNames.contains(name) {
                        issues.append(
                            "Build target '\(name)' not found in project",
                        )
                    }
                }
            }

            // Check test action
            if let testAction = scheme.testAction {
                // Check build configuration
                if !configNames.isEmpty,
                   !configNames.contains(testAction.buildConfiguration)
                {
                    issues.append(
                        "Test build configuration '\(testAction.buildConfiguration)' not found in project",
                    )
                }

                // Check testable references
                for testable in testAction.testables {
                    let name = testable.buildableReference.blueprintName
                    if !targetNames.contains(name) {
                        issues.append(
                            "Test target '\(name)' not found in project",
                        )
                    }
                }

                // Check test plan file references
                if let testPlans = testAction.testPlans {
                    let projectDir = projectURL.deletingLastPathComponent().path
                    for planRef in testPlans {
                        let ref = planRef.reference
                        // Strip "container:" prefix to get relative path
                        let relativePath: String
                        if ref.hasPrefix("container:") {
                            relativePath = String(ref.dropFirst("container:".count))
                        } else {
                            relativePath = ref
                        }

                        let absolutePath = "\(projectDir)/\(relativePath)"
                        if !FileManager.default.fileExists(atPath: absolutePath) {
                            issues.append(
                                "Test plan file not found: \(relativePath)",
                            )
                        }
                    }
                }
            }

            // Check launch action build configuration
            if let launchAction = scheme.launchAction {
                if !configNames.isEmpty,
                   !configNames.contains(launchAction.buildConfiguration)
                {
                    issues.append(
                        "Launch build configuration '\(launchAction.buildConfiguration)' not found in project",
                    )
                }
            }

            if issues.isEmpty {
                return CallTool.Result(
                    content: [.text("Scheme '\(schemeName)' is valid")],
                )
            } else {
                var result = "Scheme '\(schemeName)' has \(issues.count) issue(s):\n"
                for issue in issues {
                    result += "  - \(issue)\n"
                }
                return CallTool.Result(content: [.text(result)])
            }
        } catch {
            throw MCPError.internalError(
                "Failed to validate scheme: \(error.localizedDescription)",
            )
        }
    }
}
