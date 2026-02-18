import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct ListTypeIdentifiersTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_type_identifiers",
            description:
                "List exported and/or imported type identifiers (UTExportedTypeDeclarations / UTImportedTypeDeclarations) from a target's Info.plist",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to list type identifiers for"),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Which type identifiers to list: exported, imported, or all (default: all)"
                        ),
                        "enum": .array([
                            .string("exported"), .string("imported"), .string("all"),
                        ]),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        let kind: String
        if case let .string(k) = arguments["kind"] {
            kind = k
        } else {
            kind = "all"
        }

        guard ["exported", "imported", "all"].contains(kind) else {
            throw MCPError.invalidParams("kind must be 'exported', 'imported', or 'all'")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectDir = projectURL.deletingLastPathComponent().path

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) else {
                return CallTool.Result(
                    content: [.text("Target '\(targetName)' not found in project")]
                )
            }

            guard
                let plistPath = InfoPlistUtility.resolveInfoPlistPath(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName)
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "No Info.plist found for target '\(targetName)'. The target may use a generated Info.plist with no physical file."
                        )
                    ]
                )
            }

            let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)

            var output = ""
            var foundAny = false

            if kind == "exported" || kind == "all" {
                if let exported = plist["UTExportedTypeDeclarations"] as? [[String: Any]],
                    !exported.isEmpty
                {
                    foundAny = true
                    output += "Exported Type Identifiers in target '\(targetName)':\n"
                    output += formatTypeIdentifiers(exported)
                }
            }

            if kind == "imported" || kind == "all" {
                if let imported = plist["UTImportedTypeDeclarations"] as? [[String: Any]],
                    !imported.isEmpty
                {
                    foundAny = true
                    if !output.isEmpty { output += "\n" }
                    output += "Imported Type Identifiers in target '\(targetName)':\n"
                    output += formatTypeIdentifiers(imported)
                }
            }

            if !foundAny {
                let kindLabel: String
                switch kind {
                case "exported": kindLabel = "exported"
                case "imported": kindLabel = "imported"
                default: kindLabel = "exported or imported"
                }
                return CallTool.Result(
                    content: [
                        .text(
                            "No \(kindLabel) type identifiers found in target '\(targetName)'")
                    ]
                )
            }

            return CallTool.Result(content: [
                .text(output.trimmingCharacters(in: .whitespacesAndNewlines))
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to list type identifiers: \(error.localizedDescription)")
        }
    }

    private func formatTypeIdentifiers(_ identifiers: [[String: Any]]) -> String {
        var output = ""

        for (index, uti) in identifiers.enumerated() {
            let identifier = uti["UTTypeIdentifier"] as? String ?? "(no identifier)"
            output += "\n\(index + 1). \(identifier)\n"

            if let description = uti["UTTypeDescription"] as? String {
                output += "   Description: \(description)\n"
            }
            if let conformsTo = uti["UTTypeConformsTo"] as? [String], !conformsTo.isEmpty {
                output += "   Conforms To: \(conformsTo.joined(separator: ", "))\n"
            }
            if let tagSpec = uti["UTTypeTagSpecification"] as? [String: Any] {
                if let extensions = tagSpec["public.filename-extension"] as? [String],
                    !extensions.isEmpty
                {
                    output += "   Extensions: \(extensions.joined(separator: ", "))\n"
                } else if let ext = tagSpec["public.filename-extension"] as? String {
                    output += "   Extensions: \(ext)\n"
                }
                if let mimeTypes = tagSpec["public.mime-type"] as? [String], !mimeTypes.isEmpty {
                    output += "   MIME Types: \(mimeTypes.joined(separator: ", "))\n"
                } else if let mime = tagSpec["public.mime-type"] as? String {
                    output += "   MIME Types: \(mime)\n"
                }
            }
            if let refURL = uti["UTTypeReferenceURL"] as? String {
                output += "   Reference URL: \(refURL)\n"
            }
            if let iconName = uti["UTTypeIconName"] as? String {
                output += "   Icon: \(iconName)\n"
            }

            // Show any additional keys
            let knownKeys: Set<String> = [
                "UTTypeIdentifier", "UTTypeDescription", "UTTypeConformsTo",
                "UTTypeTagSpecification", "UTTypeReferenceURL", "UTTypeIconName",
            ]
            let additionalKeys = uti.keys.filter { !knownKeys.contains($0) }.sorted()
            for key in additionalKeys {
                output += "   \(key): \(uti[key]!)\n"
            }
        }

        return output
    }
}
