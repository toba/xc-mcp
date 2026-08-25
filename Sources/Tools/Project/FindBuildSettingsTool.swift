import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Bulk/cross-target build setting query.
///
/// Walks every native target in a project (one pbxproj load) and reports each requested setting's
/// value per (target, configuration). Optionally filters to entries whose value contains one of the
/// supplied substrings. Replaces the per-target loop pattern of calling `get_build_settings` N
/// times when auditing a single setting across an app + N frameworks.
public struct FindBuildSettingsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "find_build_settings",
            description:
                "Bulk-query build settings across the project-level buildSettings and every native target in a single pass. Given one or more setting names, returns each scope+configuration pair whose pbxproj-level buildSettings dictionary contains a match; project-level matches are labelled `[project]` (these are inherited by every target and are a common source of stray flags). Use this instead of looping `get_build_settings` per target when auditing settings like MERGEABLE_LIBRARY, MERGED_BINARY_TYPE, SUPPORTED_PLATFORMS, DEVELOPMENT_TEAM, OTHER_LDFLAGS, or SWIFT upcoming-feature flags across many targets. Reads pbxproj project- and target-level values only (does not resolve xcconfig inheritance or .xcconfig overrides — for fully resolved settings use `show_build_settings`).",
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
        let projectPath = try arguments.getRequiredString("project_path")
        let settingNames = arguments.getStringArray("settings")
        guard !settingNames.isEmpty else {
            throw MCPError.invalidParams("settings must be a non-empty array of strings")
        }

        let values = arguments.getStringArray("values")
        let valueFilters: [String]? = values.isEmpty ? nil : values

        let configFilter = arguments.getString("configuration")

        do {
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            var matches: [String] = []
            var matchCount = 0

            // Scans one build-configuration list (project-level or target-level), appending any
            // matching entries under the given label. Project-level buildSettings are a common
            // source of inherited flags (e.g. a malformed OTHER_LDFLAGS on the whole project), so
            // they must be in scope for an audit — otherwise target-only results look exhaustive
            // when they aren't.
            func scan(_ configList: XCConfigurationList?, label: String) {
                guard let configList else { return }

                for config in configList.buildConfigurations.sorted(by: { $0.name < $1.name }) {
                    if let configFilter, config.name != configFilter { continue }

                    for setting in settingNames {
                        guard let raw = config.buildSettings[setting] else { continue }
                        let valueString = renderSettingValue(raw)

                        if let valueFilters {
                            let hit = valueFilters.contains { filter in
                                switch raw {
                                    case let .string(s): s.contains(filter)
                                    case let .array(arr): arr.contains { $0.contains(filter) }
                                }
                            }
                            if !hit { continue }
                        }
                        matches.append("  \(label) [\(config.name)] \(setting) = \(valueString)")
                        matchCount += 1
                    }
                }
            }

            scan(xcodeproj.pbxproj.rootObject?.buildConfigurationList, label: "[project]")
            for target in xcodeproj.pbxproj.nativeTargets.sorted(by: { $0.name < $1.name }) {
                scan(target.buildConfigurationList, label: target.name)
            }

            let header =
                "find_build_settings in \(projectURL.lastPathComponent) (settings=\(settingNames.joined(separator: ",")), configuration=\(configFilter ?? "*"), filter=\(valueFilters?.joined(separator: ",") ?? "<none>")): \(matchCount) match\(matchCount == 1 ? "" : "es")"
            let body = matches.isEmpty ? "  (no matches)" : matches.joined(separator: "\n")

            return CallTool.Result.text("\(header)\n\(body)")
        } catch {
            throw try error.asMCPError()
        }
    }

    private func renderSettingValue(_ value: BuildSetting) -> String {
        switch value {
            case let .string(str): str
            case let .array(arr): "[\(arr.joined(separator: " "))]"
        }
    }
}
