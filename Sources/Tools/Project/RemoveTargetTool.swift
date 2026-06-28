import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveTargetTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_target",
            description: "Remove an existing target",
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
                        "description": .string("Name of the target to remove"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let projectPathKit = Path(projectURL.path)
            let preimage = PBXProjWriter.preimage(of: projectPathKit)
            let xcodeproj = try XcodeProj(path: projectPathKit)

            // Find the target to remove (check all target types, not just native)
            guard let project = xcodeproj.pbxproj.rootObject,
                  let target = project.targets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(content: [
                    .text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            }

            let projectFilename = projectURL.lastPathComponent

            // Remove every build file that embeds or links this target's product from other
            // targets' build phases (frameworks, copy-files, resources, …). XcodeProj's serializer
            // force-unwraps a build file's element name while sorting; a build file left pointing
            // at the deleted product traps the whole process — killing the MCP server — instead of
            // surfacing as an error. Clearing them first keeps serialization total. (Defect 2)
            if let productReference = target.product {
                for otherTarget in project.targets where otherTarget != target {
                    for buildPhase in otherTarget.buildPhases {
                        buildPhase.files?.removeAll { buildFile in
                            if buildFile.file == productReference {
                                xcodeproj.pbxproj.delete(object: buildFile)
                                return true
                            }
                            return false
                        }
                    }
                }

                // Sweep any remaining build files referencing the product (e.g. orphaned ones not
                // attached to a build phase).
                for buildFile in xcodeproj.pbxproj.buildFiles where buildFile.file == productReference {
                    xcodeproj.pbxproj.delete(object: buildFile)
                }
            }

            // Remove target dependencies from other targets, plus their proxy objects
            let remoteGlobalID = PBXContainerItemProxy.RemoteGlobalID.object(target)

            for otherTarget in project.targets where otherTarget != target {
                let orphaned = otherTarget.dependencies.filter { $0.target == target }

                for dependency in orphaned {
                    if let proxy = dependency.targetProxy {
                        xcodeproj.pbxproj.delete(object: proxy)
                    }
                    xcodeproj.pbxproj.delete(object: dependency)
                }
                otherTarget.dependencies.removeAll { $0.target == target }
            }

            // Remove any remaining PBXContainerItemProxy entries referencing the target
            for proxy in xcodeproj.pbxproj.containerItemProxies
                where proxy.remoteGlobalID == remoteGlobalID
            { xcodeproj.pbxproj.delete(object: proxy) }

            // Remove build phases
            for buildPhase in target.buildPhases { xcodeproj.pbxproj.delete(object: buildPhase) }

            // Remove build configuration list
            if let configList = target.buildConfigurationList {
                for config in configList.buildConfigurations {
                    xcodeproj.pbxproj.delete(object: config)
                }
                xcodeproj.pbxproj.delete(object: configList)
            }

            // Remove product reference if exists
            if let productRef = target.product {
                project.productsGroup?.children.removeAll { $0 == productRef }
                xcodeproj.pbxproj.delete(object: productRef)
            }

            // Remove target from project
            project.targets.removeAll { $0 == target }

            // Remove target group if exists
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                /// Find and remove target folder
                func removeTargetGroup(from group: PBXGroup) {
                    group.children.removeAll { element in
                        if let groupElement = element as? PBXGroup,
                           groupElement.name == targetName
                        {
                            xcodeproj.pbxproj.delete(object: groupElement)
                            return true
                        }
                        return false
                    }

                    // Recursively check child groups
                    for child in group.children {
                        if let childGroup = child as? PBXGroup {
                            removeTargetGroup(from: childGroup)
                        }
                    }
                }
                removeTargetGroup(from: mainGroup)
            }

            // Remove the target itself
            xcodeproj.pbxproj.delete(object: target)

            // Cascade the removal to every `.xctestplan` and `.xcscheme` that still references the
            // target BEFORE the project file loses it. Editing the cross-file references first
            // means no intermediate on-disk state ever has a test plan or scheme pointing at a
            // target that no longer exists — a dangling reference makes Xcode fail to load the
            // whole project. (Defect 1)
            let projectDir = projectURL.deletingLastPathComponent().path
            var editedTestPlans: [String] = []
            for plan in TestPlanFile.findFiles(under: projectDir)
                where TestPlanFile.targetNames(from: plan.json).contains(targetName)
            {
                guard var testTargets = plan.json["testTargets"] as? [[String: Any]] else { continue }
                testTargets.removeAll { entry in
                    (entry["target"] as? [String: Any])?["name"] as? String == targetName
                }
                var updated = plan.json
                updated["testTargets"] = testTargets
                try TestPlanFile.write(updated, to: plan.path)
                editedTestPlans.append(plan.path)
            }

            var editedSchemes: [String] = []
            for schemePath in SchemeTargetEditor.schemeFiles(in: resolvedProjectPath) {
                if try SchemeTargetEditor.removeTarget(
                    named: targetName, projectFilename: projectFilename, fromSchemeAt: schemePath,
                ) {
                    editedSchemes.append(schemePath)
                }
            }

            // Save project (drops the target) last, once nothing else references it.
            try PBXProjWriter.write(xcodeproj, to: projectPathKit, expectedPreimage: preimage)

            // Post-op cross-file validation: prove zero dangling references remain anywhere — not
            // just that the project file is a valid plist.
            var dangling: [String] = []
            for plan in TestPlanFile.findFiles(under: projectDir)
                where TestPlanFile.targetNames(from: plan.json).contains(targetName)
            {
                dangling.append(plan.path)
            }
            for schemePath in SchemeTargetEditor.schemeFiles(in: resolvedProjectPath)
                where SchemeTargetEditor.references(
                    target: targetName, projectFilename: projectFilename, schemeAt: schemePath,
                )
            {
                dangling.append(schemePath)
            }
            if !dangling.isEmpty {
                throw MCPError.internalError(
                    "Target '\(targetName)' was removed but these files still reference it: "
                        + dangling.joined(separator: ", "),
                )
            }

            var summary = "Successfully removed target '\(targetName)' from project"
            if !editedTestPlans.isEmpty {
                summary += "\nUpdated \(editedTestPlans.count) test plan(s): "
                    + editedTestPlans.map { URL(fileURLWithPath: $0).lastPathComponent }
                    .joined(separator: ", ")
            }
            if !editedSchemes.isEmpty {
                summary += "\nUpdated \(editedSchemes.count) scheme(s): "
                    + editedSchemes.map { URL(fileURLWithPath: $0).lastPathComponent }
                    .joined(separator: ", ")
            }

            return CallTool.Result(content: [
                .text(text: summary, annotations: nil, _meta: nil)
            ],)
        } catch {
            throw MCPError.internalError(
                "Failed to remove target from Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
