import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddToCopyFilesPhase: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_to_copy_files_phase",
            description:
                "Add files, or a linked Swift package product, to an existing Copy Files build phase. Name the phase with phase_name, or reach an unnamed phase with dst_path. Passing neither selects the target's only Copy Files phase.",
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
                        "description": .string("Name of the target containing the phase"),
                    ]),
                    "phase_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: name of the Copy Files phase to add files to, e.g. 'Embed Helpers'. If absent, the phase is located via dst_path or by being the target's only Copy Files phase.",
                        ),
                    ]),
                    "dst_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: dstPath of the Copy Files phase. Used to locate phases that have no name.",
                        ),
                    ]),
                    "files": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Paths of files to add, which must already be in the project. A Swift package product name works here too, e.g. 'TobaMarkdown', once add_package_product links the product to the target. That is Xcode's Embed & Sign for a dynamic package product.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "attributes": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Build file attributes (e.g. ['CodeSignOnCopy', 'RemoveHeadersOnCopy']). Auto-defaults for 'Embed Frameworks' phases. Use set_copy_files_attributes to change an entry that already exists.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                    "platform_filters": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Platforms each added entry builds for, e.g. ['macos']. This is Xcode's Platforms column. A multiplatform target needs it to embed a macOS-only helper without breaking its iOS build. Accepted names: macos, ios, maccatalyst, tvos, watchos, xros, visionos, driverkit. Use set_platform_filters to change an entry that already exists.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("files"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              case .array = arguments["files"]
        else { throw MCPError.invalidParams("project_path, target_name, and files are required") }

        let explicitAttributes = arguments.getOptionalStringArray("attributes")

        let platformFilters = try PlatformFilters.requested(in: arguments)

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            let copyFilesPhase = try CopyFilesPhaseLocator.locate(
                in: target,
                phaseName: arguments.getNonEmptyString("phase_name"),
                dstPath: arguments.getString("dst_path"),
                targetName: targetName,
            )
            let phaseLabel = CopyFilesPhaseLocator.label(for: copyFilesPhase)

            // Determine attributes: explicit > auto-default for Embed Frameworks > none
            let isEmbedFrameworksPhase = copyFilesPhase.name?.contains("Embed Frameworks") == true
                || copyFilesPhase.dstSubfolderSpec == .frameworks
            let attributes = explicitAttributes
                ?? (isEmbedFrameworksPhase ? ["CodeSignOnCopy", "RemoveHeadersOnCopy"] : nil)
            let settings: [String: BuildFileSetting]? =
                if let attributes { ["ATTRIBUTES": .array(attributes)] } else { nil }
            let alreadyPresentNote = Self.alreadyPresentNote(
                platformFilters: platformFilters, explicitAttributes: explicitAttributes,
            )

            // a phase Xcode wrote with no files key decodes as nil, and appending in place would
            // drop the entry
            if copyFilesPhase.files == nil { copyFilesPhase.files = [] }

            // counts the entries this call creates, which is what decides whether to write
            var attachedCount = 0

            func attach(_ buildFile: PBXBuildFile) {
                xcodeproj.pbxproj.add(object: buildFile)
                copyFilesPhase.files?.append(buildFile)
                attachedCount += 1
            }

            // reading this per file would lock the object table and copy every reference again
            let fileReferences = xcodeproj.pbxproj.fileReferences

            var addedFiles: [String] = []
            var notFoundFiles: [String] = []

            for filePath in arguments.getStringArray("files") {
                // Resolve the file path
                let resolvedFilePath: String

                do {
                    resolvedFilePath = try pathUtility.resolvePath(from: filePath)
                } catch {
                    // If resolution fails, try using the path as-is for matching
                    resolvedFilePath = filePath
                }

                let relativePath = pathUtility.makeRelativePath(from: resolvedFilePath)
                    ?? resolvedFilePath
                let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent

                // Find file reference in project
                if let fileRef = fileReferences.first(where: {
                    $0.path == relativePath || $0.path == filePath || $0.name == fileName
                        || $0.path == fileName
                }) {
                    // Check if file is already in the phase
                    let alreadyInPhase = copyFilesPhase.files?.contains { buildFile in
                        if let existingRef = buildFile.file as? PBXFileReference {
                            return existingRef.uuid == fileRef.uuid
                        }
                        return false
                    } ?? false

                    if alreadyInPhase {
                        addedFiles.append("\(fileName)\(alreadyPresentNote)")
                    } else {
                        attach(PBXBuildFile(
                            file: fileRef, settings: settings,
                            platformFilters: platformFilters.isEmpty ? nil : platformFilters,
                        ))
                        addedFiles.append(fileName)
                    }
                } else if let product = target.packageProductDependencies?.first(where: {
                    $0.productName == filePath || $0.productName == fileName
                }) {
                    // Embedding a package product reuses the dependency the target already links,
                    // the way Xcode's Embed & Sign does.
                    let alreadyInPhase = copyFilesPhase.files?.contains {
                        $0.product?.uuid == product.uuid
                    } ?? false

                    if alreadyInPhase {
                        addedFiles.append("\(product.productName)\(alreadyPresentNote)")
                    } else {
                        attach(PBXBuildFile(
                            product: product, settings: settings,
                            platformFilters: platformFilters.isEmpty ? nil : platformFilters,
                        ))
                        addedFiles.append(product.productName)
                    }
                } else {
                    notFoundFiles.append(filePath)
                }
            }

            if attachedCount > 0 {
                try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)
            }

            var message = attachedCount > 0
                ? "Added \(attachedCount) file(s) to Copy Files phase '\(phaseLabel)':"
                : "Added no file to Copy Files phase '\(phaseLabel)'. The project is unchanged."
            for file in addedFiles { message += "\n  - \(file)" }

            if !platformFilters.isEmpty {
                message += "\n\nplatformFilters = \(PlatformFilters.describe(platformFilters))"
                message += "\nUse set_platform_filters to change an entry that was already present."
            }

            if let explicitAttributes {
                message += "\n\nATTRIBUTES = \(BuildFileAttributes.describe(explicitAttributes))"
                message +=
                    "\nUse set_copy_files_attributes to change an entry that was already present."
            }

            if !notFoundFiles.isEmpty {
                message +=
                    "\n\nFiles not found in project (add a file with add_file, and link a Swift package product to target '\(targetName)' with add_package_product):"
                for file in notFoundFiles { message += "\n  - \(file)" }
            }

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Names what a repeated call leaves untouched on an entry that is already in the phase.
    private static func alreadyPresentNote(
        platformFilters: [String],
        explicitAttributes: [String]?,
    ) -> String {
        var unchanged: [String] = []
        if !platformFilters.isEmpty { unchanged.append("platform filters") }
        if explicitAttributes != nil { unchanged.append("attributes") }
        guard !unchanged.isEmpty else { return " (already present)" }
        return " (already present, \(unchanged.joined(separator: " and ")) unchanged)"
    }
}
