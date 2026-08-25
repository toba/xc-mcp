import MCP
import XCMCPCore
import Foundation

public struct ListURLTypesTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
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
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name")
        else { throw MCPError.invalidParams("project_path and target_name are required") }

        do {
            let plist: [String: AnyValue]

            switch try InfoPlistUtility.readInfoPlist(
                projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
            ) {
                case let .message(text): return CallTool.Result.text(text)
                case let .plist(contents): plist = contents
            }

            guard let urlTypes = plist["CFBundleURLTypes"]?.arrayValue?
                .compactMap(\.dictionaryValue),
                  !urlTypes.isEmpty
            else {
                return CallTool.Result.text(
                    "No URL types (CFBundleURLTypes) found in '\(targetName)'")
            }

            var output = "URL Types in target '\(targetName)':\n"

            for (index, urlType) in urlTypes.enumerated() {
                let name = urlType["CFBundleURLName"]?.stringValue ?? "(unnamed)"
                output += "\n\(index + 1). \(name)\n"

                if let schemes = urlType["CFBundleURLSchemes"]?.stringArrayValue, !schemes.isEmpty {
                    output += "   URL Schemes: \(schemes.joined(separator: ", "))\n"
                }
                if let role = urlType["CFBundleTypeRole"]?.stringValue {
                    output += "   Role: \(role)\n"
                }
                if let iconFile = urlType["CFBundleURLIconFile"]?.stringValue, !iconFile.isEmpty {
                    output += "   Icon File: \(iconFile)\n"
                }

                // Show any additional keys
                let knownKeys: Set = [
                    "CFBundleURLName", "CFBundleURLSchemes", "CFBundleTypeRole",
                    "CFBundleURLIconFile",
                ]
                for (
                    key, value
                ) in urlType.sorted(by: { $0.key < $1.key })
                    where !knownKeys.contains(key)
                { output += "   \(key): \(value.displayText)\n" }
            }

            return CallTool.Result.text(output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw try error.asMCPError()
        }
    }
}
