import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Bulk/cross-target build setting query.
///
/// Walks every native target in a project (one pbxproj load) and reports each requested
/// setting's value per (target, configuration). Optionally filters to entries whose value
/// contains one of the supplied substrings. Replaces the per-target loop pattern of calling
/// `get_build_settings` N times when auditing a single setting across an app + N frameworks.
public struct FindBuildSettingsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "find_build_settings",
            description:
                "Bulk-query build settings across every native target in a project in a single pass. Given one or more setting names, returns each target+configuration pair whose pbxproj-level buildSettings dictionary contains a match. Use this instead of looping `get_build_settings` per target when auditing settings like MERGEABLE_LIBRARY, MERGED_BINARY_TYPE, SUPPORTED_PLATFORMS, DEVELOPMENT_TEAM, or SWIFT upcoming-feature flags across many targets. Reads pbxproj target-level values only (does not resolve xcconfig inheritance or .xcconfig overrides — for fully resolved settings use `show_build_settings`).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "settings": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Build setting names to look up (e.g. ['MERGEABLE_LIBRARY','MERGED_BINARY_TYPE']). Match is exact on the key.",
                        ),
                    ]),
                    "values": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Optional substring filter: only report entries whose value (or any element if the value is an array) contains one of these strings. Case-sensitive.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Limit to a single configuration name (e.g. 'Debug', 'Release'). If omitted, all configurations are scanned.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("settings")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }
        guard case let .array(settingsArray) = arguments["settings"], !settingsArray.isEmpty else {
            throw MCPError.invalidParams("settings must be a non-empty array of strings")
        }
        let settingNames: [String] = settingsArray.compactMap {
            if case let .string(s) = $0 { return s } else { return nil }
        }
        guard !settingNames.isEmpty else {
            throw MCPError.invalidParams("settings must contain at least one string")
        }

        let valueFilters: [String]?
        if case let .array(valuesArray) = arguments["values"] {
            let strings: [String] = valuesArray.compactMap {
                if case let .string(s) = $0 { return s } else { return nil }
            }
            valueFilters = strings.isEmpty ? nil : strings
        } else {
            valueFilters = nil
        }

        let configFilter: String?
        if case let .string(c) = arguments["configuration"] { configFilter = c } else {
            configFilter = nil
        }

        do {
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            var matches: [String] = []
            var matchCount = 0
            for target in xcodeproj.pbxproj.nativeTargets.sorted(by: { $0.name < $1.name }) {
                guard let configList = target.buildConfigurationList else { continue }
                for config in configList.buildConfigurations.sorted(by: { $0.name < $1.name }) {
                    if let configFilter, config.name != configFilter { continue }
                    for setting in settingNames {
                        guard let raw = config.buildSettings[setting] else { continue }
                        let valueString = renderSettingValue(raw)
                        if let valueFilters {
                            let hit = valueFilters.contains { filter in
                                switch raw {
                                    case let .string(s): return s.contains(filter)
                                    case let .array(arr): return arr.contains { $0.contains(filter) }
                                }
                            }
                            if !hit { continue }
                        }
                        matches.append(
                            "  \(target.name) [\(config.name)] \(setting) = \(valueString)",
                        )
                        matchCount += 1
                    }
                }
            }

            let header =
                "find_build_settings in \(projectURL.lastPathComponent) (settings=\(settingNames.joined(separator: ",")), configuration=\(configFilter ?? "*"), filter=\(valueFilters?.joined(separator: ",") ?? "<none>")): \(matchCount) match\(matchCount == 1 ? "" : "es")"
            let body = matches.isEmpty ? "  (no matches)" : matches.joined(separator: "\n")

            return CallTool.Result(content: [
                .text(text: "\(header)\n\(body)", annotations: nil, _meta: nil),
            ])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func renderSettingValue(_ value: BuildSetting) -> String {
        switch value {
            case let .string(str): return str
            case let .array(arr): return "[\(arr.joined(separator: " "))]"
        }
    }
}
