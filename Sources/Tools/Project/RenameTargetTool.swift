import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RenameTargetTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "rename_target",
            description: "Rename an existing target in-place, updating all references",
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
                        "description": .string("Current name of the target to rename"),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("New name for the target"),
                    ]),
                    "new_bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier for the renamed target (optional)",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("new_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let newName = arguments.getString("new_name")
        else {
            throw MCPError.invalidParams("project_path, target_name, and new_name are required")
        }

        let newBundleIdentifier = arguments.getString("new_bundle_identifier")

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            // Find the target to rename
            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            // Check new name doesn't already exist
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == newName }) {
                return CallTool.Result.text("Target '\(newName)' already exists in project")
            }

            // A product path follows PRODUCT_NAME, which the caller may set to anything. Read it
            // before step 2 rewrites it.
            let productFollowsTargetName = Self.productFollowsTargetName(
                target: target, targetName: targetName,
            )

            var rewrites = RewriteLog()
            var notes: [String] = []

            // 1. Update target name and product name
            target.name = newName
            target.productName = newName

            // 2. Update build settings in all configurations
            if let configList = target.buildConfigurationList {
                for config in configList.buildConfigurations {
                    // replace PRODUCT_NAME when it names the old target
                    if config.buildSettings["PRODUCT_NAME"]?.stringValue == targetName {
                        config.buildSettings["PRODUCT_NAME"] = .string(newName)
                        rewrites.add("\(newName) PRODUCT_NAME: '\(targetName)' -> '\(newName)'")
                    }

                    // replace PRODUCT_MODULE_NAME when it names the old target
                    if config.buildSettings["PRODUCT_MODULE_NAME"]?.stringValue == targetName {
                        config.buildSettings["PRODUCT_MODULE_NAME"] = .string(newName)
                        rewrites.add(
                            "\(newName) PRODUCT_MODULE_NAME: '\(targetName)' -> '\(newName)'")
                    }

                    for key in ["INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"] {
                        rewritePathSetting(
                            in: &config.buildSettings,
                            key: key,
                            oldName: targetName,
                            newName: newName,
                            scope: newName,
                            rewrites: &rewrites,
                        )
                    }

                    // set the bundle identifier when the caller supplied one
                    if let newBundleIdentifier {
                        config.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] = .string(
                            newBundleIdentifier,
                        )
                        config.buildSettings["BUNDLE_IDENTIFIER"] = .string(newBundleIdentifier)
                    }
                }
            }

            // 3. Cross-target build settings scan
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                guard let configList = otherTarget.buildConfigurationList else { continue }

                for config in configList.buildConfigurations {
                    // replace TEST_TARGET_NAME on an exact match
                    if config.buildSettings["TEST_TARGET_NAME"]?.stringValue == targetName {
                        config.buildSettings["TEST_TARGET_NAME"] = .string(newName)
                        rewrites.add(
                            "\(otherTarget.name) TEST_TARGET_NAME: "
                                + "'\(targetName)' -> '\(newName)'")
                    }

                    let pathKeys = [
                        "TEST_HOST", "LD_RUNPATH_SEARCH_PATHS", "FRAMEWORK_SEARCH_PATHS",
                    ]

                    for key in pathKeys {
                        rewritePathSetting(
                            in: &config.buildSettings,
                            key: key,
                            oldName: targetName,
                            newName: newName,
                            scope: otherTarget.name,
                            rewrites: &rewrites,
                        )
                    }
                }
            }

            // 4. Update dependencies in other targets
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for dependency in otherTarget.dependencies where dependency.target == target {
                    dependency.name = newName
                    if let proxy = dependency.targetProxy { proxy.remoteInfo = newName }
                    rewrites.add("\(otherTarget.name) dependency: '\(targetName)' -> '\(newName)'")
                }
            }

            // A target's product is renamed with its target in step 6. Rewriting it from a copy
            // phase as well would apply the new name twice.
            let productReferences = Set(
                xcodeproj.pbxproj.nativeTargets.compactMap(\.product).map { ObjectIdentifier($0) },
            )

            // 5. Update embed/copy-files phases referencing a file named after this target
            for otherTarget in xcodeproj.pbxproj.nativeTargets {
                for buildPhase in otherTarget.buildPhases {
                    guard let copyPhase = buildPhase as? PBXCopyFilesBuildPhase else { continue }

                    for buildFile in copyPhase.files ?? [] {
                        guard let fileRef = buildFile.file,
                              let path = fileRef.path,
                              !productReferences.contains(ObjectIdentifier(fileRef))
                        else { continue }

                        let updated = Self.renaming(
                            path: path, oldName: targetName, newName: newName,
                        )
                        guard updated != path else { continue }

                        fileRef.path = updated
                        rewrites.add("\(otherTarget.name) copied file: '\(path)' -> '\(updated)'")
                    }
                }
            }

            // 6. Update product reference
            if let product = target.product {
                if productFollowsTargetName {
                    if let path = product.path {
                        let updated = Self.renaming(
                            path: path, oldName: targetName, newName: newName,
                        )

                        if updated != path {
                            product.path = updated
                            rewrites.add("\(newName) product path: '\(path)' -> '\(updated)'")
                        }
                    }
                    if let name = product.name {
                        let updated = Self.renaming(
                            path: name, oldName: targetName, newName: newName,
                        )

                        if updated != name {
                            product.name = updated
                            rewrites.add("\(newName) product name: '\(name)' -> '\(updated)'")
                        }
                    }
                } else if let path = product.path {
                    notes.append(
                        "left the product path '\(path)' alone because PRODUCT_NAME does not "
                            + "track the target name",
                    )
                }
            }

            // 7. Rename target group in main group hierarchy
            if let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            {
                func renameGroup(in group: PBXGroup) {
                    for child in group.children {
                        if let childGroup = child as? PBXGroup,
                           childGroup.name == targetName
                        {
                            childGroup.name = newName
                            if childGroup.path == targetName { childGroup.path = newName }
                        }
                        if let childGroup = child as? PBXGroup { renameGroup(in: childGroup) }
                    }
                }
                renameGroup(in: mainGroup)
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            // 8. Update scheme files
            let schemesUpdated = updateSchemeFiles(
                projectPath: projectURL.path,
                oldName: targetName,
                newName: newName,
            )

            var message = "Successfully renamed target '\(targetName)' to '\(newName)'"

            if schemesUpdated > 0 {
                message +=
                    " (updated \(schemesUpdated) scheme file\(schemesUpdated == 1 ? "" : "s"))"
            }

            let lines = rewrites.lines

            if !lines.isEmpty {
                message += "\n\nRewrote \(lines.count) reference\(lines.count == 1 ? "" : "s"):"
                for line in lines { message += "\n  - \(line)" }
            }

            for note in notes { message += "\n\nNote: \(note)" }

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Collects one line per rewrite, so a setting changed in two configurations reports once.
    private struct RewriteLog {
        private(set) var lines: [String] = []
        private var seen: Set<String> = []

        mutating func add(_ line: String) { if seen.insert(line).inserted { lines.append(line) } }
    }

    /// Values of PRODUCT_NAME that keep the product named after the target.
    private static let targetNameMacros: Set<String> = ["$(TARGET_NAME)", "${TARGET_NAME}"]

    /// Whether the target's product still takes its name from the target name.
    ///
    /// A configuration that sets PRODUCT_NAME to anything else names the product itself, so a
    /// rename must leave the product reference alone.
    private static func productFollowsTargetName(
        target: PBXNativeTarget,
        targetName: String,
    ) -> Bool {
        (target.buildConfigurationList?.buildConfigurations ?? []).allSatisfy { config in
            guard let value = config.buildSettings["PRODUCT_NAME"]?.stringValue else { return true }
            return value == targetName || targetNameMacros.contains(value)
        }
    }

    /// Renames the path components that name the target, and leaves every other component alone.
    ///
    /// A component matches when it equals the old name, or when the part before its first dot
    /// equals the old name. A rename of `jig` therefore rewrites `jig` and `jig.app`, and leaves
    /// `jig-direct.app` and `jig-Info.plist` untouched.
    private static func renaming(path: String, oldName: String, newName: String) -> String {
        guard !oldName.isEmpty, path.contains(oldName) else { return path }

        var didChange = false
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let renamed = components.map { component -> String in
            guard component.hasPrefix(oldName) else { return String(component) }

            let suffix = component.dropFirst(oldName.count)
            guard suffix.isEmpty || suffix.hasPrefix(".") else { return String(component) }

            didChange = true
            return newName + suffix
        }

        return didChange ? renamed.joined(separator: "/") : path
    }

    /// Renames the target inside a build setting holding a path, or a list of paths.
    private func rewritePathSetting(
        in buildSettings: inout BuildSettings,
        key: String,
        oldName: String,
        newName: String,
        scope: String,
        rewrites: inout RewriteLog,
    ) {
        guard let value = buildSettings[key] else { return }

        switch value {
            case let .string(path):
                let updated = Self.renaming(path: path, oldName: oldName, newName: newName)
                guard updated != path else { return }

                buildSettings[key] = .string(updated)
                rewrites.add("\(scope) \(key): '\(path)' -> '\(updated)'")
            case let .array(paths):
                let updated = paths.map {
                    Self.renaming(path: $0, oldName: oldName, newName: newName)
                }
                guard updated != paths else { return }

                buildSettings[key] = .array(updated)

                for (before, after) in zip(paths, updated) where before != after {
                    rewrites.add("\(scope) \(key): '\(before)' -> '\(after)'")
                }
        }
    }

    /// Scan scheme files and replace BuildableName/BlueprintName references. Returns the number of
    /// scheme files updated.
    private func updateSchemeFiles(
        projectPath: String,
        oldName: String,
        newName: String,
    ) -> Int {
        let fm = FileManager.default
        let schemeDirs = SchemePathResolver.schemeDirs(for: projectPath)

        var updatedCount = 0

        for schemeDir in schemeDirs {
            guard let files = try? fm.contentsOfDirectory(atPath: schemeDir) else { continue }

            for file in files where file.hasSuffix(".xcscheme") {
                let schemePath = "\(schemeDir)/\(file)"
                guard var content = try? String(contentsOfFile: schemePath, encoding: .utf8) else {
                    continue
                }

                let original = content

                // Replace BuildableName (preserves extension)
                content = content.replacingOccurrences(
                    of: "BuildableName = \"\(oldName).",
                    with: "BuildableName = \"\(newName).",
                )

                // a command line tool product carries no extension
                content = content.replacingOccurrences(
                    of: "BuildableName = \"\(oldName)\"",
                    with: "BuildableName = \"\(newName)\"",
                )

                // Replace BlueprintName
                content = content.replacingOccurrences(
                    of: "BlueprintName = \"\(oldName)\"",
                    with: "BlueprintName = \"\(newName)\"",
                )

                if content != original {
                    try? content.write(toFile: schemePath, atomically: true, encoding: .utf8)
                    updatedCount += 1
                }
            }
        }

        return updatedCount
    }
}
