import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct CreateSchemeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "create_scheme",
            description: "Create an Xcode scheme (.xcscheme) file for a project",
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
                        "description": .string("Name for the new scheme"),
                    ]),
                    "build_target": .object([
                        "type": .string("string"),
                        "description": .string("Target name for the BuildAction"),
                    ]),
                    "test_targets": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Target names to include in TestAction as testables",
                        ),
                    ]),
                    "test_plan_paths": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Paths to .xctestplan files (first is default test plan)",
                        ),
                    ]),
                    "build_configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration name (defaults to Debug)"),
                    ]),
                    "pre_actions": .object([
                        "type": .string("array"),
                        "items": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "title": .object(["type": .string("string")]),
                                "script_text": .object(["type": .string("string")]),
                            ]),
                        ]),
                        "description": .string(
                            "Pre-build shell script actions (each with title and script_text)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("scheme_name"), .string("build_target"),
                ]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(schemeName) = arguments["scheme_name"],
              case let .string(buildTargetName) = arguments["build_target"]
        else {
            throw MCPError.invalidParams(
                "project_path, scheme_name, and build_target are required",
            )
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let projectURL = URL(fileURLWithPath: resolvedProjectPath)

        let buildConfiguration: String
        if case let .string(config) = arguments["build_configuration"] {
            buildConfiguration = config
        } else {
            buildConfiguration = "Debug"
        }

        // Ensure shared schemes directory exists
        let schemesDir = "\(resolvedProjectPath)/xcshareddata/xcschemes"
        let schemePath = "\(schemesDir)/\(schemeName).xcscheme"

        if FileManager.default.fileExists(atPath: schemePath) {
            return CallTool.Result(
                content: [.text("Scheme '\(schemeName)' already exists")],
            )
        }

        do {
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Resolve build target
            guard
                let buildTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == buildTargetName
                })
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Build target '\(buildTargetName)' not found in project",
                        ),
                    ],
                )
            }

            let containerPath = "container:\(projectURL.lastPathComponent)"

            let buildRef = XCScheme.BuildableReference(
                referencedContainer: containerPath,
                blueprint: buildTarget,
                buildableName: buildableName(for: buildTarget),
                blueprintName: buildTargetName,
            )

            // BuildAction
            var preActions: [XCScheme.ExecutionAction] = []
            if case let .array(preActionValues) = arguments["pre_actions"] {
                for preActionValue in preActionValues {
                    if case let .object(dict) = preActionValue,
                       case let .string(title) = dict["title"],
                       case let .string(scriptText) = dict["script_text"]
                    {
                        preActions.append(
                            XCScheme.ExecutionAction(
                                scriptText: scriptText,
                                title: title,
                                environmentBuildable: buildRef,
                            ),
                        )
                    }
                }
            }

            let buildActionEntry = XCScheme.BuildAction.Entry(
                buildableReference: buildRef,
                buildFor: XCScheme.BuildAction.Entry.BuildFor.default,
            )

            let buildAction = XCScheme.BuildAction(
                buildActionEntries: [buildActionEntry],
                preActions: preActions,
                parallelizeBuild: true,
                buildImplicitDependencies: true,
            )

            // TestAction
            var testables: [XCScheme.TestableReference] = []
            if case let .array(testTargetValues) = arguments["test_targets"] {
                for testTargetValue in testTargetValues {
                    guard case let .string(testTargetName) = testTargetValue else { continue }
                    guard
                        let testTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
                            $0.name == testTargetName
                        })
                    else {
                        return CallTool.Result(
                            content: [
                                .text(
                                    "Test target '\(testTargetName)' not found in project",
                                ),
                            ],
                        )
                    }

                    let testRef = XCScheme.BuildableReference(
                        referencedContainer: containerPath,
                        blueprint: testTarget,
                        buildableName: buildableName(for: testTarget),
                        blueprintName: testTargetName,
                    )

                    testables.append(
                        XCScheme.TestableReference(
                            skipped: false,
                            buildableReference: testRef,
                        ),
                    )
                }
            }

            var testPlanRefs: [XCScheme.TestPlanReference]?
            if case let .array(testPlanPaths) = arguments["test_plan_paths"] {
                testPlanRefs = []
                for (index, testPlanPath) in testPlanPaths.enumerated() {
                    guard case let .string(planPath) = testPlanPath else { continue }
                    let resolvedPlanPath = try pathUtility.resolvePath(from: planPath)

                    // Make path relative via container reference
                    let projectDir = projectURL.deletingLastPathComponent().path
                    let relativePath: String
                    if resolvedPlanPath.hasPrefix(projectDir) {
                        relativePath = String(
                            resolvedPlanPath.dropFirst(projectDir.count + 1),
                        )
                    } else {
                        relativePath = resolvedPlanPath
                    }

                    testPlanRefs?.append(
                        XCScheme.TestPlanReference(
                            reference: "container:\(relativePath)",
                            default: index == 0,
                        ),
                    )
                }
            }

            let testAction = XCScheme.TestAction(
                buildConfiguration: buildConfiguration,
                macroExpansion: buildRef,
                testables: testables,
                testPlans: testPlanRefs,
            )

            // LaunchAction
            let launchAction = XCScheme.LaunchAction(
                runnable: XCScheme.BuildableProductRunnable(
                    buildableReference: buildRef,
                ),
                buildConfiguration: buildConfiguration,
            )

            // AnalyzeAction and ArchiveAction
            let analyzeAction = XCScheme.AnalyzeAction(
                buildConfiguration: buildConfiguration,
            )
            let archiveAction = XCScheme.ArchiveAction(
                buildConfiguration: buildConfiguration == "Debug" ? "Release" : buildConfiguration,
                revealArchiveInOrganizer: true,
            )

            let scheme = XCScheme(
                name: schemeName,
                lastUpgradeVersion: nil,
                version: nil,
                buildAction: buildAction,
                testAction: testAction,
                launchAction: launchAction,
                analyzeAction: analyzeAction,
                archiveAction: archiveAction,
            )

            // Create directory if needed
            try FileManager.default.createDirectory(
                atPath: schemesDir,
                withIntermediateDirectories: true,
            )

            try scheme.write(path: Path(schemePath), override: false)

            var summary = "Created scheme '\(schemeName)' at \(schemePath)"
            summary += "\n  Build target: \(buildTargetName)"
            summary += "\n  Configuration: \(buildConfiguration)"
            if !testables.isEmpty {
                let names = testables.map(\.buildableReference.blueprintName)
                summary += "\n  Test targets: \(names.joined(separator: ", "))"
            }
            if let refs = testPlanRefs, !refs.isEmpty {
                summary += "\n  Test plans: \(refs.count)"
            }

            return CallTool.Result(content: [.text(summary)])
        } catch {
            throw MCPError.internalError(
                "Failed to create scheme: \(error.localizedDescription)",
            )
        }
    }

    private func buildableName(for target: PBXNativeTarget) -> String {
        if let productType = target.productType,
           let ext = productType.fileExtension
        {
            return "\(target.name).\(ext)"
        }
        return target.name
    }
}
