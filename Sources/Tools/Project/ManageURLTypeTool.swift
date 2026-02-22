import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ManageURLTypeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "manage_url_type",
            description:
            "Add, update, or remove a URL type (CFBundleURLTypes entry) in a target's Info.plist. URL types define custom URL schemes the app can handle.",
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
                            "URL type identifier (CFBundleURLName). Used as the primary key for lookup.",
                        ),
                    ]),
                    "url_schemes": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "URL schemes for CFBundleURLSchemes (e.g. [\"myapp\", \"myapp-dev\"])",
                        ),
                    ]),
                    "role": .object([
                        "type": .string("string"),
                        "description": .string(
                            "CFBundleTypeRole: Editor, Viewer, Shell, or None",
                        ),
                    ]),
                    "icon_file": .object([
                        "type": .string("string"),
                        "description": .string("CFBundleURLIconFile name (macOS only)"),
                    ]),
                    "additional_properties": .object([
                        "type": .string("string"),
                        "description": .string(
                            "JSON string of additional key-value pairs to set on the URL type entry",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("action"),
                    .string("name"),
                ]),
            ]),
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
                    content: [.text("Target '\(targetName)' not found in project")],
                )
            }

            // Resolve or materialize Info.plist
            var plistPath = InfoPlistUtility.resolveInfoPlistPath(
                xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
            )

            if plistPath == nil {
                plistPath = try InfoPlistUtility.materializeInfoPlist(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
                    projectPath: Path(projectURL.path),
                )
            }

            guard let resolvedPlistPath = plistPath else {
                throw MCPError.internalError(
                    "Failed to resolve or create Info.plist for target '\(targetName)'",
                )
            }

            var plist = try InfoPlistUtility.readInfoPlist(path: resolvedPlistPath)
            var urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]] ?? []

            switch action {
                case "add":
                    if urlTypes.contains(where: {
                        ($0["CFBundleURLName"] as? String) == name
                    }) {
                        return CallTool.Result(
                            content: [
                                .text(
                                    "URL type '\(name)' already exists in target '\(targetName)'",
                                ),
                            ],
                        )
                    }

                    var entry: [String: Any] = ["CFBundleURLName": name]
                    applyFields(to: &entry, from: arguments)
                    urlTypes.append(entry)

                    plist["CFBundleURLTypes"] = urlTypes
                    try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                    return CallTool.Result(
                        content: [
                            .text(
                                "Successfully added URL type '\(name)' to target '\(targetName)'",
                            ),
                        ],
                    )

                case "update":
                    guard
                        let index = urlTypes.firstIndex(where: {
                            ($0["CFBundleURLName"] as? String) == name
                        })
                    else {
                        return CallTool.Result(
                            content: [
                                .text(
                                    "URL type '\(name)' not found in target '\(targetName)'",
                                ),
                            ],
                        )
                    }

                    var entry = urlTypes[index]
                    applyFields(to: &entry, from: arguments)
                    urlTypes[index] = entry

                    plist["CFBundleURLTypes"] = urlTypes
                    try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                    return CallTool.Result(
                        content: [
                            .text(
                                "Successfully updated URL type '\(name)' in target '\(targetName)'",
                            ),
                        ],
                    )

                case "remove":
                    guard
                        let index = urlTypes.firstIndex(where: {
                            ($0["CFBundleURLName"] as? String) == name
                        })
                    else {
                        return CallTool.Result(
                            content: [
                                .text(
                                    "URL type '\(name)' not found in target '\(targetName)'",
                                ),
                            ],
                        )
                    }

                    urlTypes.remove(at: index)

                    if urlTypes.isEmpty {
                        plist.removeValue(forKey: "CFBundleURLTypes")
                    } else {
                        plist["CFBundleURLTypes"] = urlTypes
                    }
                    try InfoPlistUtility.writeInfoPlist(plist, toPath: resolvedPlistPath)

                    return CallTool.Result(
                        content: [
                            .text(
                                "Successfully removed URL type '\(name)' from target '\(targetName)'",
                            ),
                        ],
                    )

                default:
                    throw MCPError.invalidParams("action must be 'add', 'update', or 'remove'")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to manage URL type: \(error.localizedDescription)",
            )
        }
    }

    private func applyFields(to entry: inout [String: Any], from arguments: [String: Value]) {
        if case let .array(schemes) = arguments["url_schemes"] {
            entry["CFBundleURLSchemes"] = schemes.compactMap { value -> String? in
                if case let .string(s) = value { return s }
                return nil
            }
        }
        if case let .string(role) = arguments["role"] {
            entry["CFBundleTypeRole"] = role
        }
        if case let .string(iconFile) = arguments["icon_file"] {
            entry["CFBundleURLIconFile"] = iconFile
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
