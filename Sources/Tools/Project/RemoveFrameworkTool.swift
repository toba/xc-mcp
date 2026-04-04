import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveFrameworkTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_framework",
            description: "Remove a framework dependency from an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "framework_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the framework to remove (e.g., UIKit, UIKit.framework, or path to custom framework)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to remove framework from (optional, removes from all targets if omitted)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("framework_name")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(frameworkName) = arguments["framework_name"]
        else {
            throw MCPError.invalidParams(
                "project_path and framework_name are required",
            )
        }

        let targetName: String?
        if case let .string(name) = arguments["target_name"] {
            targetName = name
        } else {
            targetName = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Normalize framework name for matching
            let frameworkFileName: String
            let baseName: String
            if frameworkName.hasSuffix(".framework") {
                frameworkFileName = frameworkName
                baseName = String(frameworkName.dropLast(".framework".count))
            } else {
                frameworkFileName = "\(frameworkName).framework"
                baseName = frameworkName
            }

            // Determine targets to process
            let targets: [PBXNativeTarget]
            if let targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
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
                targets = [target]
            } else {
                targets = xcodeproj.pbxproj.nativeTargets
            }

            func matchesFramework(_ fileRef: PBXFileReference) -> Bool {
                fileRef.name == frameworkFileName
                    || fileRef.name == baseName
                    || fileRef.path == baseName
                    || fileRef.path == frameworkFileName
            }

            var removedFromTargets: [String] = []
            var orphanedFileRefs: [PBXFileReference] = []

            for target in targets {
                var removedFromThisTarget = false

                // Remove from frameworks build phase
                if let frameworkPhase = target.buildPhases.first(where: {
                    $0 is PBXFrameworksBuildPhase
                }) as? PBXFrameworksBuildPhase {
                    if let files = frameworkPhase.files {
                        let matching = files.filter { buildFile in
                            if let fileRef = buildFile.file as? PBXFileReference {
                                return matchesFramework(fileRef)
                            }
                            return false
                        }
                        for buildFile in matching {
                            if let fileRef = buildFile.file as? PBXFileReference {
                                orphanedFileRefs.append(fileRef)
                            }
                            frameworkPhase.files?.removeAll { $0 === buildFile }
                            xcodeproj.pbxproj.delete(object: buildFile)
                            removedFromThisTarget = true
                        }
                    }
                }

                // Remove from embed frameworks (copy files) phases
                for phase in target.buildPhases {
                    if let copyPhase = phase as? PBXCopyFilesBuildPhase,
                       copyPhase.dstSubfolderSpec == .frameworks
                       || copyPhase.dstSubfolder == .frameworks
                    {
                        if let files = copyPhase.files {
                            let matching = files.filter { buildFile in
                                if let fileRef = buildFile.file as? PBXFileReference {
                                    return matchesFramework(fileRef)
                                }
                                return false
                            }
                            for buildFile in matching {
                                copyPhase.files?.removeAll { $0 === buildFile }
                                xcodeproj.pbxproj.delete(object: buildFile)
                                removedFromThisTarget = true
                            }
                        }
                    }
                }

                if removedFromThisTarget {
                    removedFromTargets.append(target.name)
                }
            }

            // Clean up orphaned file references (not used by any remaining build file)
            for fileRef in orphanedFileRefs {
                // Skip BUILT_PRODUCTS_DIR references — they belong to other targets' products
                if fileRef.sourceTree == .buildProductsDir {
                    continue
                }

                let stillUsed = xcodeproj.pbxproj.buildFiles.contains { buildFile in
                    buildFile.file === fileRef
                }

                if !stillUsed {
                    removeFromGroups(fileRef, in: xcodeproj)
                    xcodeproj.pbxproj.delete(object: fileRef)
                }
            }

            if removedFromTargets.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "Framework '\(frameworkName)' not found in \(targetName.map { "target '\($0)'" } ?? "any target")",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let targetList = removedFromTargets.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(text:
                        "Successfully removed framework '\(frameworkName)' from target(s): \(targetList)",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove framework from Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func removeFromGroups(_ fileRef: PBXFileReference, in xcodeproj: XcodeProj) {
        guard let project = xcodeproj.pbxproj.rootObject,
              let mainGroup = project.mainGroup
        else {
            return
        }
        removeFromGroup(fileRef, in: mainGroup)
    }

    @discardableResult
    private func removeFromGroup(_ fileRef: PBXFileReference, in group: PBXGroup) -> Bool {
        if let index = group.children.firstIndex(where: { $0 === fileRef }) {
            group.children.remove(at: index)
            return true
        }
        for child in group.children {
            if let childGroup = child as? PBXGroup {
                if removeFromGroup(fileRef, in: childGroup) {
                    return true
                }
            }
        }
        return false
    }
}
