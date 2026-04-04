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
                        "description": .string(
                            "Target name for the BuildAction (use build_targets for multiple)",
                        ),
                    ]),
                    "build_targets": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Target names for the BuildAction (first target is primary for launch/test). Overrides build_target if both provided",
                        ),
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
                    .string("project_path"), .string("scheme_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(schemeName) = arguments["scheme_name"]
        else {
            throw MCPError.invalidParams(
                "project_path and scheme_name are required",
            )
        }

        // Resolve build target names: prefer build_targets array, fall back to build_target string
        let buildTargetNames: [String]
        if case let .array(targets) = arguments["build_targets"] {
            buildTargetNames =
                targets
                    .compactMap { if case let .string(name) = $0 { name } else { nil } }
        } else if case let .string(single) = arguments["build_target"] {
            buildTargetNames = [single]
        } else {
            throw MCPError.invalidParams(
                "Either build_target or build_targets is required",
            )
        }

        guard !buildTargetNames.isEmpty else {
            throw MCPError.invalidParams("build_targets must not be empty")
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
                content: [.text(
                    text: "Scheme '\(schemeName)' already exists",
                    annotations: nil,
                    _meta: nil,
                )],
            )
        }

        do {
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))
            let containerPath = "container:\(projectURL.lastPathComponent)"

            // Resolve all build targets
            var buildRefs: [XCScheme.BuildableReference] = []
            for targetName in buildTargetNames {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(text:
                                "Build target '\(targetName)' not found in project",
                                annotations: nil, _meta: nil),
                        ],
                    )
                }
                buildRefs.append(
                    XCScheme.BuildableReference(
                        referencedContainer: containerPath,
                        blueprint: target,
                        buildableName: buildableName(for: target),
                        blueprintName: targetName,
                    ),
                )
            }

            // First build ref is the primary (used for launch, test macro expansion, pre-actions)
            let primaryBuildRef = buildRefs[0]

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
                                environmentBuildable: primaryBuildRef,
                            ),
                        )
                    }
                }
            }

            let buildActionEntries = buildRefs.map {
                XCScheme.BuildAction.Entry(
                    buildableReference: $0,
                    buildFor: XCScheme.BuildAction.Entry.BuildFor.default,
                )
            }

            let buildAction = XCScheme.BuildAction(
                buildActionEntries: buildActionEntries,
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
                                .text(text:
                                    "Test target '\(testTargetName)' not found in project",
                                    annotations: nil, _meta: nil),
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
                macroExpansion: primaryBuildRef,
                testables: testables,
                testPlans: testPlanRefs,
            )

            // LaunchAction
            let launchAction = XCScheme.LaunchAction(
                runnable: XCScheme.BuildableProductRunnable(
                    buildableReference: primaryBuildRef,
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
            summary += "\n  Build targets: \(buildTargetNames.joined(separator: ", "))"
            summary += "\n  Configuration: \(buildConfiguration)"
            if !testables.isEmpty {
                let names = testables.map(\.buildableReference.blueprintName)
                summary += "\n  Test targets: \(names.joined(separator: ", "))"
            }
            if let refs = testPlanRefs, !refs.isEmpty {
                summary += "\n  Test plans: \(refs.count)"
            }

            return CallTool.Result(content: [.text(text: summary, annotations: nil, _meta: nil)])
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
