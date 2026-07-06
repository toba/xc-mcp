import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ValidateSchemeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
            annotations: .readOnly,
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

        guard let schemePath = SchemePathResolver.findScheme(
            named: schemeName, in: resolvedProjectPath,
        ) else {
            return CallTool.Result(content: [
                .text(
                    text: "Scheme '\(schemeName)' not found in project",
                    annotations: nil,
                    _meta: nil,
                )
            ],)
        }

        do {
            let scheme = try XCScheme(pathString: schemePath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let targetNames = Set(xcodeproj.pbxproj.nativeTargets.map(\.name))
            let configNames = Set(xcodeproj.pbxproj.buildConfigurations.map(\.name))

            var issues: [String] = []

            // Check build action target references
            if let buildAction = scheme.buildAction {
                for entry in buildAction.buildActionEntries {
                    let name = entry.buildableReference.blueprintName
                    if !targetNames.contains(name) {
                        issues.append("Build target '\(name)' not found in project")
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
                        issues.append("Test target '\(name)' not found in project")
                    }
                }

                // Check test plan file references
                if let testPlans = testAction.testPlans {
                    let projectDir = projectURL.deletingLastPathComponent().path

                    for planRef in testPlans {
                        let ref = planRef.reference
                        // Strip "container:" prefix to get relative path
                        let relativePath: String
                        relativePath = ref.hasPrefix("container:")
                            ? String(ref.dropFirst("container:".count))
                            : ref

                        let absolutePath = "\(projectDir)/\(relativePath)"
                        if !FileManager.default.fileExists(atPath: absolutePath) {
                            issues.append("Test plan file not found: \(relativePath)")
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

            // Check that any StoreKit configuration reference resolves to a file on disk. A wrong
            // relative depth (e.g. ../../ instead of ../../../) silently points at nothing, leaving
            // StoreKit testing disabled with no error — exactly the failure mode in pzg-2cv.
            let schemeDir = URL(fileURLWithPath: schemePath).deletingLastPathComponent()

            for (action, identifier) in SetSchemeStoreKitConfigTool.storeKitIdentifiers(
                inSchemeAt: schemePath,
            ) {
                let resolved = schemeDir.appendingPathComponent(identifier)
                    .standardizedFileURL.path

                if !FileManager.default.fileExists(atPath: resolved) {
                    issues.append(
                        "StoreKit configuration referenced by the "
                            + "\(SetSchemeStoreKitConfigTool.friendlyName(action)) action "
                            + "('\(identifier)') does not resolve to a file "
                            + "(expected at \(resolved))",
                    )
                }
            }

            // Flag a .storekit shipped inside an application target's Copy Bundle Resources — a
            // StoreKit config belongs in a test bundle for SKTestSession, never in the app.
            for target in xcodeproj.pbxproj.nativeTargets
                where target.productType == .application
            {
                for phase in target.buildPhases {
                    guard let resources = phase as? PBXResourcesBuildPhase else { continue }

                    for buildFile in resources.files ?? [] {
                        guard let ref = buildFile.file as? PBXFileReference,
                              (ref.path ?? ref.name ?? "").hasSuffix(".storekit") else { continue }
                        issues.append(
                            "StoreKit config '\(ref.name ?? ref.path ?? "?")' is in application "
                                + "target '\(target.name)' Copy Bundle Resources — it should not "
                                + "ship inside the app; move it to a test target",
                        )
                    }
                }
            }

            if issues.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "Scheme '\(schemeName)' is valid",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            } else {
                var result = "Scheme '\(schemeName)' has \(issues.count) issue(s):\n"
                for issue in issues { result += "  - \(issue)\n" }
                return CallTool.Result(content: [.text(text: result, annotations: nil, _meta: nil)])
            }
        } catch {
            throw MCPError.internalError("Failed to validate scheme: \(error.localizedDescription)")
        }
    }
}
