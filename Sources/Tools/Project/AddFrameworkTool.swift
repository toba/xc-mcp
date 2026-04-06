import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddFrameworkTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_framework",
            description: "Add framework dependencies",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to add framework to"),
                    ]),
                    "framework_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the framework to add (e.g., UIKit, Foundation, or path to custom framework)",
                        ),
                    ]),
                    "embed": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to embed the framework (for custom frameworks, optional, defaults to false)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("framework_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(frameworkName) = arguments["framework_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and framework_name are required",
            )
        }

        let embed: Bool
        if case let .bool(shouldEmbed) = arguments["embed"] {
            embed = shouldEmbed
        } else {
            embed = false
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "Target '\(targetName)' not found in project",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            // Find existing frameworks build phase (may need to create one via text edit)
            let existingFrameworksPhase = target.buildPhases.first(
                where: { $0 is PBXFrameworksBuildPhase },
            ) as? PBXFrameworksBuildPhase

            // Check if this is a static library (.a) that already exists as a build product
            let isStaticLibrary = frameworkName.hasSuffix(".a")

            // Before classifying as system framework, check if a matching product
            // reference exists in BUILT_PRODUCTS_DIR (e.g. a local framework target).
            // This handles bare names like "Core" that match "Core.framework" products.
            let hasLocalProduct: Bool
            if !isStaticLibrary, !frameworkName.contains("/"),
               !frameworkName.hasSuffix(".framework")
            {
                let candidateName = "\(frameworkName).framework"
                hasLocalProduct =
                    xcodeproj.pbxproj.fileReferences.contains {
                        $0.sourceTree == .buildProductsDir
                            && ($0.path == candidateName || $0.name == candidateName)
                    }
                    || xcodeproj.pbxproj.referenceProxies.contains {
                        $0.sourceTree == .buildProductsDir
                            && ($0.path == candidateName || $0.name == candidateName)
                    }
            } else {
                hasLocalProduct = false
            }

            // Determine if this is a system framework or custom framework
            let isSystemFramework =
                !hasLocalProduct && !isStaticLibrary && !frameworkName.contains("/")
                    && !frameworkName.hasSuffix(".framework")
            let frameworkFileName: String
            let frameworkPath: String

            // Developer frameworks that live in Xcode.app, not in the SDK
            let developerFrameworks: Set = [
                "XcodeKit", "XCTest", "SpriteKit", "SceneKit",
            ]
            let isDeveloperFramework =
                isSystemFramework
                    && developerFrameworks
                    .contains(frameworkName)

            if isSystemFramework {
                frameworkFileName = "\(frameworkName).framework"
                if isDeveloperFramework {
                    frameworkPath = "Library/Frameworks/\(frameworkFileName)"
                } else {
                    frameworkPath = "System/Library/Frameworks/\(frameworkFileName)"
                }
            } else if isStaticLibrary {
                frameworkFileName = frameworkName
                frameworkPath = frameworkName
            } else if hasLocalProduct {
                // Bare name matching a local framework product (e.g. "Core" → "Core.framework")
                frameworkFileName = "\(frameworkName).framework"
                frameworkPath = frameworkFileName
            } else {
                // Resolve custom framework path
                let resolvedFrameworkPath = try pathUtility.resolvePath(from: frameworkName)
                frameworkFileName = URL(fileURLWithPath: resolvedFrameworkPath).lastPathComponent
                // Use relative path from project for file reference
                frameworkPath =
                    pathUtility.makeRelativePath(from: resolvedFrameworkPath)
                        ?? resolvedFrameworkPath
            }

            // Check if framework already exists (could be PBXFileReference or PBXReferenceProxy)
            let frameworkExists =
                existingFrameworksPhase?.files?.contains { buildFile in
                    guard let fileElement = buildFile.file else { return false }
                    return fileElement.name == frameworkFileName
                        || fileElement.path == frameworkName
                        || fileElement.path == frameworkFileName
                } ?? false

            if frameworkExists {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Framework '\(frameworkName)' already exists in target '\(targetName)'",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            let q = PBXProjTextEditor.quotePBX

            // --- Text-based edits ---
            var text = try PBXProjTextEditor.read(projectPath: resolvedProjectPath)

            // 1. Find or create file reference
            let fileRefUUID: String
            var needsGroupEntry = false

            if isStaticLibrary {
                if let existingRef = xcodeproj.pbxproj.fileReferences.first(where: {
                    ($0.path == frameworkName || $0.name == frameworkName)
                        && ($0.sourceTree == .buildProductsDir
                            || $0.explicitFileType == "archive.ar")
                }) {
                    fileRefUUID = existingRef.uuid
                } else {
                    fileRefUUID = PBXProjTextEditor.generateUUID()
                    let line =
                        "\t\t\(fileRefUUID) /* \(frameworkFileName) */ = {isa = PBXFileReference; explicitFileType = archive.ar; name = \(q(frameworkFileName)); path = \(q(frameworkPath)); sourceTree = BUILT_PRODUCTS_DIR; };"
                    text = try PBXProjTextEditor.insertBlockInSection(
                        text, section: "PBXFileReference", blockLines: [line],
                    )
                }
            } else if isSystemFramework {
                fileRefUUID = PBXProjTextEditor.generateUUID()
                let sourceTree = isDeveloperFramework ? "DEVELOPER_DIR" : "SDKROOT"
                let line =
                    "\t\t\(fileRefUUID) /* \(frameworkFileName) */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = \(q(frameworkFileName)); path = \(q(frameworkPath)); sourceTree = \(sourceTree); };"
                text = try PBXProjTextEditor.insertBlockInSection(
                    text, section: "PBXFileReference", blockLines: [line],
                )
                needsGroupEntry = true
            } else if let existingRef = xcodeproj.pbxproj.fileReferences.first(where: {
                $0.sourceTree == .buildProductsDir
                    && ($0.path == frameworkFileName || $0.name == frameworkFileName)
            }) {
                // Reuse existing BUILT_PRODUCTS_DIR reference
                fileRefUUID = existingRef.uuid
            } else if let existingProxy = xcodeproj.pbxproj.referenceProxies.first(where: {
                $0.sourceTree == .buildProductsDir
                    && ($0.path == frameworkFileName || $0.name == frameworkFileName)
            }) {
                // Reuse existing PBXReferenceProxy (cross-project reference)
                fileRefUUID = existingProxy.uuid
            } else {
                fileRefUUID = PBXProjTextEditor.generateUUID()
                let line =
                    "\t\t\(fileRefUUID) /* \(frameworkFileName) */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = \(q(frameworkFileName)); path = \(q(frameworkPath)); sourceTree = \"<group>\"; };"
                text = try PBXProjTextEditor.insertBlockInSection(
                    text, section: "PBXFileReference", blockLines: [line],
                )
                needsGroupEntry = true
            }

            // 2. Add to Frameworks group (only for new file references that aren't build products)
            if needsGroupEntry {
                let frameworksGroup = xcodeproj.pbxproj.rootObject?.mainGroup?.children
                    .first(where: { ($0 as? PBXGroup)?.name == "Frameworks" }) as? PBXGroup

                if let groupUUID = frameworksGroup?.uuid {
                    text = try PBXProjTextEditor.addReference(
                        text, blockUUID: groupUUID, field: "children",
                        refUUID: fileRefUUID, comment: frameworkFileName,
                    )
                } else {
                    // Create Frameworks group
                    let groupUUID = PBXProjTextEditor.generateUUID()
                    let groupBlock = [
                        "\t\t\(groupUUID) /* Frameworks */ = {",
                        "\t\t\tisa = PBXGroup;",
                        "\t\t\tchildren = (",
                        "\t\t\t\t\(fileRefUUID) /* \(frameworkFileName) */,",
                        "\t\t\t);",
                        "\t\t\tname = Frameworks;",
                        "\t\t\tsourceTree = \"<group>\";",
                        "\t\t};",
                    ]
                    text = try PBXProjTextEditor.insertBlockInSection(
                        text, section: "PBXGroup", blockLines: groupBlock,
                    )
                    // Add group to main group's children
                    if let mainGroupUUID = xcodeproj.pbxproj.rootObject?.mainGroup?.uuid {
                        text = try PBXProjTextEditor.addReference(
                            text, blockUUID: mainGroupUUID, field: "children",
                            refUUID: groupUUID, comment: "Frameworks",
                        )
                    }
                }
            }

            // 3. Find or create frameworks build phase
            let phaseUUID: String
            if let existingPhase = existingFrameworksPhase {
                phaseUUID = existingPhase.uuid
            } else {
                phaseUUID = PBXProjTextEditor.generateUUID()
                let phaseBlock = [
                    "\t\t\(phaseUUID) /* Frameworks */ = {",
                    "\t\t\tisa = PBXFrameworksBuildPhase;",
                    "\t\t\tbuildActionMask = 2147483647;",
                    "\t\t\tfiles = (",
                    "\t\t\t);",
                    "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
                    "\t\t};",
                ]
                text = try PBXProjTextEditor.insertBlockInSection(
                    text, section: "PBXFrameworksBuildPhase", blockLines: phaseBlock,
                )
                text = try PBXProjTextEditor.addReference(
                    text, blockUUID: target.uuid, field: "buildPhases",
                    refUUID: phaseUUID, comment: "Frameworks",
                )
            }

            // 4. Create build file and add to frameworks build phase
            let buildFileUUID = PBXProjTextEditor.generateUUID()
            let buildFileLine =
                "\t\t\(buildFileUUID) /* \(frameworkFileName) in Frameworks */ = {isa = PBXBuildFile; fileRef = \(fileRefUUID) /* \(frameworkFileName) */; };"
            text = try PBXProjTextEditor.insertBlockInSection(
                text, section: "PBXBuildFile", blockLines: [buildFileLine],
            )
            text = try PBXProjTextEditor.addReference(
                text, blockUUID: phaseUUID, field: "files",
                refUUID: buildFileUUID, comment: "\(frameworkFileName) in Frameworks",
            )

            // 5. Handle embed
            if embed, !isSystemFramework {
                let embedPhaseUUID: String
                if let existing = target.buildPhases.first(where: {
                    if let copyPhase = $0 as? PBXCopyFilesBuildPhase {
                        return copyPhase.dstSubfolderSpec == .frameworks
                            || copyPhase.dstSubfolder == .frameworks
                    }
                    return false
                }) {
                    embedPhaseUUID = existing.uuid
                } else {
                    let newUUID = PBXProjTextEditor.generateUUID()
                    embedPhaseUUID = newUUID
                    let embedBlock = [
                        "\t\t\(newUUID) /* Embed Frameworks */ = {",
                        "\t\t\tisa = PBXCopyFilesBuildPhase;",
                        "\t\t\tbuildActionMask = 2147483647;",
                        "\t\t\tdstPath = \"\";",
                        "\t\t\tdstSubfolderSpec = 10;",
                        "\t\t\tfiles = (",
                        "\t\t\t);",
                        "\t\t\tname = \"Embed Frameworks\";",
                        "\t\t\trunOnlyForDeploymentPostprocessing = 0;",
                        "\t\t};",
                    ]
                    text = try PBXProjTextEditor.insertBlockInSection(
                        text, section: "PBXCopyFilesBuildPhase", blockLines: embedBlock,
                    )
                    text = try PBXProjTextEditor.addReference(
                        text, blockUUID: target.uuid, field: "buildPhases",
                        refUUID: newUUID, comment: "Embed Frameworks",
                    )
                }

                let embedBuildFileUUID = PBXProjTextEditor.generateUUID()
                let embedBuildFileLine =
                    "\t\t\(embedBuildFileUUID) /* \(frameworkFileName) in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = \(fileRefUUID) /* \(frameworkFileName) */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };"
                text = try PBXProjTextEditor.insertBlockInSection(
                    text, section: "PBXBuildFile", blockLines: [embedBuildFileLine],
                )
                text = try PBXProjTextEditor.addReference(
                    text, blockUUID: embedPhaseUUID, field: "files",
                    refUUID: embedBuildFileUUID,
                    comment: "\(frameworkFileName) in Embed Frameworks",
                )
            }

            // 6. Handle developer framework search paths
            if isDeveloperFramework {
                if let configList = target.buildConfigurationList {
                    for config in configList.buildConfigurations {
                        let existing = config.buildSettings["FRAMEWORK_SEARCH_PATHS"]
                        if existing == nil {
                            text = try PBXProjTextEditor.addBuildSettingArray(
                                text, configUUID: config.uuid,
                                key: "FRAMEWORK_SEARCH_PATHS",
                                values: ["$(inherited)", "$(DEVELOPER_FRAMEWORKS_DIR)"],
                            )
                        }
                    }
                }
            }

            try PBXProjTextEditor.write(text, projectPath: resolvedProjectPath)

            let embedText = embed && !isSystemFramework ? " (embedded)" : ""
            return CallTool.Result(
                content: [
                    .text(text:
                        "Successfully added framework '\(frameworkName)' to target '\(targetName)'\(embedText)",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add framework to Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
