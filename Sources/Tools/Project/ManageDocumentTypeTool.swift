import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct ManageDocumentTypeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "manage_document_type",
            description:
                "Add, update, or remove a document type (CFBundleDocumentTypes entry) in a target's Info.plist",
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
                    "name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Document type name (CFBundleTypeName). Used as the primary key for lookup."
                        ),
                    ]),
                    "content_types": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "UTI strings for LSItemContentTypes (e.g. [\"app.toba.thesis.project\"])"
                        ),
                    ]),
                    "role": .object([
                        "type": .string("string"),
                        "description": .string(
                            "CFBundleTypeRole: Editor, Viewer, Shell, QLGenerator, or None"),
                    ]),
                    "handler_rank": .object([
                        "type": .string("string"),
                        "description": .string(
                            "LSHandlerRank: Owner, Default, Alternate, or None"),
                    ]),
                    "document_class": .object([
                        "type": .string("string"),
                        "description": .string("NSDocumentClass name"),
                    ]),
                    "icon_file": .object([
                        "type": .string("string"),
                        "description": .string("CFBundleTypeIconFile name"),
                    ]),
                    "is_package": .object([
                        "type": .string("boolean"),
                        "description": .string("LSTypeIsPackage boolean"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the document type entry"
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("action"),
                    .string("name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(targetName) = arguments["target_name"],
            case let .string(action) = arguments["action"],
            case let .string(name) = arguments["name"]
        else {
            throw MCPError.invalidParams("project_path, target_name, action, and name are required")
        }

        guard ["add", "update", "remove"].contains(action) else {
            throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
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
            var documentTypes = plist["CFBundleDocumentTypes"] as? [[String: Any]] ?? []

            switch action {
            case "add":
                if documentTypes.contains(where: {
                    ($0["CFBundleTypeName"] as? String) == name
                }) {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Document type '\(name)' already exists in target '\(targetName)'")
                        ]
                    )
                }

                var entry: [String: Any] = ["CFBundleTypeName": name]
                applyFields(to: &entry, from: arguments)
                documentTypes.append(entry)

                plist["CFBundleDocumentTypes"] = documentTypes
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully added document type '\(name)' to target '\(targetName)'")
                    ]
                )

            case "update":
                guard
                    let index = documentTypes.firstIndex(where: {
                        ($0["CFBundleTypeName"] as? String) == name
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Document type '\(name)' not found in target '\(targetName)'")
                        ]
                    )
                }

                var entry = documentTypes[index]
                applyFields(to: &entry, from: arguments)
                documentTypes[index] = entry

                plist["CFBundleDocumentTypes"] = documentTypes
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully updated document type '\(name)' in target '\(targetName)'"
                        )
                    ]
                )

            case "remove":
                guard
                    let index = documentTypes.firstIndex(where: {
                        ($0["CFBundleTypeName"] as? String) == name
                    })
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Document type '\(name)' not found in target '\(targetName)'")
                        ]
                    )
                }

                documentTypes.remove(at: index)

                if documentTypes.isEmpty {
                    plist.removeValue(forKey: "CFBundleDocumentTypes")
                } else {
                    plist["CFBundleDocumentTypes"] = documentTypes
                }
                try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully removed document type '\(name)' from target '\(targetName)'"
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
                "Failed to manage document type: \(error.localizedDescription)")
        }
    }

    private func applyFields(to entry: inout [String: Any], from arguments: [String: Value]) {
        if case let .array(contentTypes) = arguments["content_types"] {
            entry["LSItemContentTypes"] = contentTypes.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
        }
        if case let .string(role) = arguments["role"] {
            entry["CFBundleTypeRole"] = role
        }
        if case let .string(rank) = arguments["handler_rank"] {
            entry["LSHandlerRank"] = rank
        }
        if case let .string(docClass) = arguments["document_class"] {
            entry["NSDocumentClass"] = docClass
        }
        if case let .string(iconFile) = arguments["icon_file"] {
            entry["CFBundleTypeIconFile"] = iconFile
        }
        if case let .bool(isPackage) = arguments["is_package"] {
            entry["LSTypeIsPackage"] = isPackage
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
