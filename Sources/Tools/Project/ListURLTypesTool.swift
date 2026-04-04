import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListURLTypesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "list_url_types",
            description:
            "List all URL types (CFBundleURLTypes) declared in a target's Info.plist. URL types define custom URL schemes the app can handle.",
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
                        "description": .string("Name of the target to list URL types for"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_name")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams("project_path and target_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectDir = projectURL.deletingLastPathComponent().path

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) else {
                return CallTool.Result(
                    content: [.text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            }

            guard
                let plistPath = InfoPlistUtility.resolveInfoPlistPath(
                    xcodeproj: xcodeproj, projectDir: projectDir, targetName: targetName,
                )
            else {
                return CallTool.Result(
                    content: [
                        .text(text:
                            "No Info.plist found for target '\(targetName)'. The target may use a generated Info.plist with no physical file.",
                            annotations: nil, _meta: nil),
                    ],
                )
            }

            let plist = try InfoPlistUtility.readInfoPlist(path: plistPath)

            guard let urlTypes = plist["CFBundleURLTypes"] as? [[String: Any]],
                  !urlTypes.isEmpty
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "No URL types (CFBundleURLTypes) found in '\(targetName)'",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            var output = "URL Types in target '\(targetName)':\n"

            for (index, urlType) in urlTypes.enumerated() {
                let name = urlType["CFBundleURLName"] as? String ?? "(unnamed)"
                output += "\n\(index + 1). \(name)\n"

                if let schemes = urlType["CFBundleURLSchemes"] as? [String], !schemes.isEmpty {
                    output += "   URL Schemes: \(schemes.joined(separator: ", "))\n"
                }
                if let role = urlType["CFBundleTypeRole"] as? String {
                    output += "   Role: \(role)\n"
                }
                if let iconFile = urlType["CFBundleURLIconFile"] as? String, !iconFile.isEmpty {
                    output += "   Icon File: \(iconFile)\n"
                }

                // Show any additional keys
                let knownKeys: Set = [
                    "CFBundleURLName", "CFBundleURLSchemes", "CFBundleTypeRole",
                    "CFBundleURLIconFile",
                ]
                let additionalKeys = urlType.keys.filter { !knownKeys.contains($0) }.sorted()
                for key in additionalKeys {
                    output += "   \(key): \(urlType[key]!)\n"
                }
            }

            return CallTool.Result(content: [
                .text(
                    text: output.trimmingCharacters(in: .whitespacesAndNewlines),
                    annotations: nil,
                    _meta: nil,
                ),
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to list URL types: \(error.localizedDescription)",
            )
        }
    }
}
