import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct ManageTypeIdentifierTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "manage_type_identifier",
            description:
                "Add, update, or remove an exported or imported type identifier (UTExportedTypeDeclarations / UTImportedTypeDeclarations) in a target's Info.plist",
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
                        "description": .string("Name of the target"),
                    ]),
                    "action": .object([
                        "type": .string("string"),
                        "description": .string("Action to perform: add, update, or remove"),
                        "enum": .array([.string("add"), .string("update"), .string("remove")]),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Whether this is an exported or imported type identifier"),
                        "enum": .array([.string("exported"), .string("imported")]),
                    ]),
                    "identifier": .object([
                        "type": .string("string"),
                        "description": .string(
                            "UTTypeIdentifier (e.g. app.toba.thesis.project). Used as the primary key."
                        ),
                    ]),
                    "description": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeDescription (human-readable description)"),
                    ]),
                    "conforms_to": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "UTTypeConformsTo array (e.g. [\"com.apple.package\"])"),
                    ]),
                    "extensions": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "File extensions (maps to UTTypeTagSpecification[\"public.filename-extension\"])"
                        ),
                    ]),
                    "mime_types": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "MIME types (maps to UTTypeTagSpecification[\"public.mime-type\"])"),
                    ]),
                    "reference_url": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeReferenceURL"),
                    ]),
                    "icon_name": .object([
                        "type": .string("string"),
                        "description": .string("UTTypeIconName"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the type identifier entry"
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("action"),
                    .string("kind"), .string("identifier"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(action) = arguments["action"],
            case let .string(kind) = arguments["kind"],
            case let .string(identifier) = arguments["identifier"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, action, kind, and identifier are required")
        }

        guard ["add", "update", "remove"].contains(action) else {
            throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
        }
        guard ["exported", "imported"].contains(kind) else {
            throw MCPError.invalidParams("kind must be 'exported' or 'imported'")
        }

        let plistKey =
            kind == "exported" ? "UTExportedTypeDeclarations" : "UTImportedTypeDeclarations"
        let kindLabel = kind == "exported" ? "exported" : "imported"

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

            // Resolve or materialize Info.plist
            var plistPath = InfoPlistUtility.resolveInfoPlistPath(
                xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName)

            if plistPath == nil {
                plistPath = try InfoPlistUtility.materializeInfoPlist(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
                    projectPath: Path(projectURL.path))
            }

            guard let resolvedPlistPath = plistPath else {
                throw MCPError.internalError(
                    "Failed to resolve or create Info.plist for target '\(targetName)'")
            }

            var plist = try InfoPlistUtility.readInfoPlist(path: resolvedPlistPath)
            var typeDecls = plist[plistKey] as? [[String: Any]] ?? []

            switch action {
            case "add":
                if typeDecls.contains(where: {
                    ($0["UTTypeIdentifier"] as? String) == identifier
                }) {
                    return CallTool.Result(
                        content: [
                            .text(
                                "\(kindLabel.capitalized) type identifier '\(identifier)' already exists in target '\(targetName)'"
                            )
                        ]
                    )
                }

                var entry: [String: Any] = ["UTTypeIdentifier": identifier]
                applyFields(to: &entry, from: arguments)
                typeDecls.append(entry)

                plist[plistKey] = typeDecls
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully added \(kindLabel) type identifier '\(identifier)' to target '\(targetName)'"
                        )
                    ]
                )

            case "update":
                guard
                    let index = typeDecls.firstIndex(where: {
                        ($0["UTTypeIdentifier"] as? String) == identifier
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "\(kindLabel.capitalized) type identifier '\(identifier)' not found in target '\(targetName)'"
                            )
                        ]
                    )
                }

                var entry = typeDecls[index]
                applyFields(to: &entry, from: arguments)
                typeDecls[index] = entry

                plist[plistKey] = typeDecls
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully updated \(kindLabel) type identifier '\(identifier)' in target '\(targetName)'"
                        )
                    ]
                )

            case "remove":
                guard
                    let index = typeDecls.firstIndex(where: {
                        ($0["UTTypeIdentifier"] as? String) == identifier
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "\(kindLabel.capitalized) type identifier '\(identifier)' not found in target '\(targetName)'"
                            )
                        ]
                    )
                }

                typeDecls.remove(at: index)

                if typeDecls.isEmpty {
                    plist.removeValue(forKey: plistKey)
                } else {
                    plist[plistKey] = typeDecls
                }
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully removed \(kindLabel) type identifier '\(identifier)' from target '\(targetName)'"
                        )
                    ]
                )

            default:
                throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to manage type identifier: \(error.localizedDescription)")
        }
    }

    private func applyFields(to entry: inout [String: Any], from arguments: [String: Value]) {
        if case let .string(desc) = arguments["description"] {
            entry["UTTypeDescription"] = desc
        }
        if case let .array(conformsTo) = arguments["conforms_to"] {
            entry["UTTypeConformsTo"] = conformsTo.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
        }

        // Build UTTypeTagSpecification from extensions and mime_types
        var tagSpec = entry["UTTypeTagSpecification"] as? [String: Any] ?? [:]
        var tagSpecModified = false

        if case let .array(extensions) = arguments["extensions"] {
            let exts = extensions.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
            if !exts.isEmpty {
                tagSpec["public.filename-extension"] = exts
                tagSpecModified = true
            }
        }
        if case let .array(mimeTypes) = arguments["mime_types"] {
            let mimes = mimeTypes.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
            if !mimes.isEmpty {
                tagSpec["public.mime-type"] = mimes
                tagSpecModified = true
            }
        }
        if tagSpecModified {
            entry["UTTypeTagSpecification"] = tagSpec
        }

        if case let .string(refURL) = arguments["reference_url"] {
            entry["UTTypeReferenceURL"] = refURL
        }
        if case let .string(iconName) = arguments["icon_name"] {
            entry["UTTypeIconName"] = iconName
        }
        if case let .string(jsonString) = arguments["additional_properties"],
            let jsonData = jsonString.data(using: .utf8),
            let additionalProps = try? JSONSerialization.jsonObject(with: jsonData)
                as? [String: Any]
        {
            for (key, value) in additionalProps {
                entry[key] = value
            }
        }
    }
}
