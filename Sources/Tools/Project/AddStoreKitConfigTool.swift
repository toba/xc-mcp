import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Adds a StoreKit configuration (`.storekit`) file to a project *coherently* — the multi-part
/// operation `add_file` cannot model on its own.
///
/// A correct `.storekit` setup is three coordinated edits:
///  1. A project **file reference** so the config appears in Edit Scheme → Run → Options → StoreKit
///     Configuration (that picker only lists project-member `.storekit` files).
///  2. Membership in a **test target's** resources when tests use
///     `SKTestSession(configurationFileNamed:)` — the config must live in the *test bundle*, never
///     in the shipping app's Copy Bundle Resources.
///  3. The scheme's Run and/or Test `StoreKitConfigurationFileReference`, stored as a path relative
///     to the `.xcscheme` file.
///
/// This tool performs 1 always, 2 when `test_target` is given, and 3 when `scheme_name` is given —
/// and warns when it detects the classic misconfigurations (config in an app target, wrong target
/// kind, scheme not wired).
public struct AddStoreKitConfigTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_storekit_config",
            description: """
                Add a StoreKit configuration (.storekit) file to a project the right way, in one call: \
                create the project file reference (so it shows in the scheme's StoreKit Configuration \
                picker), optionally add it to a test target's resources for \
                SKTestSession(configurationFileNamed:), and wire the scheme's Run/Test \
                StoreKitConfigurationFileReference with the correct scheme-relative path. Prefer this \
                over add_file for .storekit files — add_file would drop the config into a Copy Bundle \
                Resources phase and leave the scheme un-wired.
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "storekit_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .storekit configuration file (must exist on disk)",
                        ),
                    ]),
                    "scheme_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Scheme to wire the StoreKit reference into (optional but recommended — "
                                + "without it the config is added to the project but stays inactive)",
                        ),
                    ]),
                    "test_target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of a test target to add the config to (its test bundle resources), "
                                + "required for SKTestSession(configurationFileNamed:). Must be a "
                                + "unit/UI test bundle — a .storekit must not ship inside an app.",
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Group to add the file reference to, supports slash-separated paths. "
                                + "Optional, defaults to the main group.",
                        ),
                    ]),
                    "target_actions": .object([
                        "type": .string("string"),
                        "enum": .array([.string("launch"), .string("test"), .string("both")]),
                        "description": .string(
                            "Which scheme actions to wire: launch (Run), test (Test), or both "
                                + "(default)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("storekit_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let projectPath = try arguments.getRequiredString("project_path")
        let storekitPath = try arguments.getRequiredString("storekit_path")
        let schemeName = arguments.getString("scheme_name")
        let testTargetName = arguments.getString("test_target")
        let groupName = arguments.getString("group_name")

        let targetActions = arguments.getString("target_actions") ?? "both"
        let elementNames: [String]

        switch targetActions {
            case "launch": elementNames = ["LaunchAction"]
            case "test": elementNames = ["TestAction"]
            case "both": elementNames = SetSchemeStoreKitConfigTool.editableActionNames
            default:
                throw MCPError.invalidParams("target_actions must be 'launch', 'test', or 'both'")
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let resolvedStorekitPath = try pathUtility.resolvePath(from: storekitPath)

        guard resolvedStorekitPath.hasSuffix(".storekit") else {
            throw MCPError.invalidParams(
                "storekit_path must point to a .storekit file (got \(resolvedStorekitPath))",
            )
        }
        guard FileManager.default.fileExists(atPath: resolvedStorekitPath) else {
            return Self.message("StoreKit configuration not found at \(resolvedStorekitPath)")
        }

        var steps: [String] = []
        var warnings: [String] = []

        // --- Project edits: file reference + optional test-target membership ---
        do {
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projPath = Path(projectURL.path)
            let preimage = PBXProjWriter.preimage(of: projPath)
            let xcodeproj = try XcodeProj(path: projPath)

            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            let targetGroup: PBXGroup

            if let groupName {
                targetGroup = try mainGroup.resolveGroupPath(groupName)
            } else {
                targetGroup = mainGroup
            }

            let projectRoot = projectURL.deletingLastPathComponent().path
            let fileName = URL(fileURLWithPath: resolvedStorekitPath).lastPathComponent

            let fileReference = try AddFileTool.resolveOrCreateFileReference(
                resolvedFilePath: resolvedStorekitPath,
                in: targetGroup,
                pbxproj: xcodeproj.pbxproj,
                projectRoot: projectRoot,
                basePath: pathUtility.basePath,
            )
            steps.append(
                "added project file reference '\(fileName)' (now selectable in the "
                    + "scheme's StoreKit Configuration picker)")

            // Optional: add to the named test target's resources so SKTestSession can load it.
            if let testTargetName {
                guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == testTargetName
                }) else {
                    throw MCPError.invalidParams("Target '\(testTargetName)' not found in project")
                }

                // Only add the config to genuine test bundles. Adding it to a shipping target's
                // Copy Bundle Resources is the exact antipattern this tool exists to prevent, so a
                // non-test target is warned and skipped rather than silently mis-bundled.
                if Self.isTestBundle(target) {
                    let added = Self.addToResources(
                        fileReference: fileReference,
                        target: target,
                        pbxproj: xcodeproj.pbxproj,
                    )
                    steps.append(
                        added
                            ? "added to test target '\(testTargetName)' resources (for "
                                + "SKTestSession(configurationFileNamed:))"
                            : "already a member of test target '\(testTargetName)' resources")
                } else {
                    warnings.append(
                        "target '\(testTargetName)' is not a unit/UI test bundle "
                            + "(product type: \(target.productType?.rawValue ?? "unknown")) — "
                            + "skipped adding the config to its resources, since a .storekit added "
                            + "to a shipping target gets bundled into the app. Pass the test target "
                            + "that runs SKTestSession instead.")
                }
            }

            // Guardrail: flag the config sitting in any application target's Copy Bundle Resources.
            for appTarget in xcodeproj.pbxproj.nativeTargets
                where Self.isApplication(appTarget)
                && Self.resourcesContains(fileReference, target: appTarget)
            {
                warnings.append(
                    "'\(fileName)' is in application target '\(appTarget.name)' Copy "
                        + "Bundle Resources — a StoreKit config should not ship inside the app. Remove "
                        + "it from that target with remove_file (or the app target's resources).")
            }

            try PBXProjWriter.write(xcodeproj, to: projPath, expectedPreimage: preimage)
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add StoreKit config to project: \(error.localizedDescription)",
            )
        }

        // --- Scheme wiring ---
        if let schemeName {
            guard let schemePath = SchemePathResolver.findScheme(
                named: schemeName, in: resolvedProjectPath,
            ) else {
                warnings.append(
                    "scheme '\(schemeName)' not found — the config was added to the "
                        + "project but no scheme reference was wired; StoreKit testing stays disabled "
                        + "until a scheme's StoreKitConfigurationFileReference points at it.")
                return Self.result(steps: steps, warnings: warnings)
            }

            let identifier = SchemePathResolver.schemeRelativeIdentifier(
                for: resolvedStorekitPath, schemePath: schemePath,
            )

            do {
                let (edited, skipped) = try SetSchemeStoreKitConfigTool.applyStoreKitReference(
                    schemePath: schemePath,
                    identifier: identifier,
                    isAdd: true,
                    elementNames: elementNames,
                )

                if edited.isEmpty {
                    warnings.append(
                        "scheme '\(schemeName)' has none of the requested actions "
                            + "(\(elementNames.map(SetSchemeStoreKitConfigTool.friendlyName).joined(separator: ", "))) "
                            + "— nothing was wired.")
                } else {
                    let list = edited.map(SetSchemeStoreKitConfigTool.friendlyName)
                        .joined(separator: " + ")
                    steps.append("wired scheme '\(schemeName)' \(list) to '\(identifier)'")
                }
                if !skipped.isEmpty {
                    warnings.append(
                        "scheme actions not present, skipped: "
                            + skipped.map(SetSchemeStoreKitConfigTool.friendlyName)
                            .joined(separator: ", "))
                }
            } catch {
                throw MCPError.internalError(
                    "Added the config to the project but failed to wire scheme "
                        + "'\(schemeName)': \(error.localizedDescription)",
                )
            }
        } else {
            warnings.append(
                "no scheme_name given — the config is in the project but no scheme's "
                    + "StoreKitConfigurationFileReference points at it, so it stays inactive (None in "
                    + "Edit Scheme). Re-run with scheme_name, or use set_scheme_storekit_config.")
        }

        return Self.result(steps: steps, warnings: warnings)
    }

    // MARK: - Helpers

    /// Whether a target is a unit or UI test bundle (the valid home for an SKTestSession config).
    private static func isTestBundle(_ target: PBXNativeTarget) -> Bool {
        switch target.productType {
            case .unitTestBundle, .uiTestBundle, .ocUnitTestBundle: true
            default: false
        }
    }

    /// Whether a target produces a shipping application (a `.storekit` here would be bundled).
    private static func isApplication(_ target: PBXNativeTarget) -> Bool {
        switch target.productType {
            case .application,
                 .watchApp,
                 .watch2App,
                 .messagesApplication,
                 .onDemandInstallCapableApplication: true
            default: false
        }
    }

    /// Whether `target`'s resources build phase already embeds `fileReference`.
    private static func resourcesContains(
        _ fileReference: PBXFileReference,
        target: PBXNativeTarget,
    ) -> Bool {
        for phase in target.buildPhases {
            guard let resources = phase as? PBXResourcesBuildPhase else { continue }
            if (resources.files ?? []).contains(where: { $0.file === fileReference }) {
                return true
            }
        }
        return false
    }

    /// Adds `fileReference` to `target`'s resources build phase (creating the phase if absent),
    /// skipping if already present. Returns whether a new build file was added.
    private static func addToResources(
        fileReference: PBXFileReference,
        target: PBXNativeTarget,
        pbxproj: PBXProj,
    ) -> Bool {
        if resourcesContains(fileReference, target: target) { return false }

        let buildFile = PBXBuildFile(file: fileReference)
        pbxproj.add(object: buildFile)

        if let resources = target.buildPhases.first(where: { $0 is PBXResourcesBuildPhase })
            as? PBXResourcesBuildPhase
        {
            resources.files = (resources.files ?? []) + [buildFile]
        } else {
            let resources = PBXResourcesBuildPhase(files: [buildFile])
            pbxproj.add(object: resources)
            target.buildPhases.append(resources)
        }
        return true
    }

    private static func result(steps: [String], warnings: [String]) -> CallTool.Result {
        var text = "StoreKit config:\n"
        for step in steps { text += "  ✓ \(step)\n" }

        if !warnings.isEmpty {
            text += "\nWarnings:\n"
            for warning in warnings { text += "  ⚠︎ \(warning)\n" }
        }
        return message(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func message(_ text: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }
}
