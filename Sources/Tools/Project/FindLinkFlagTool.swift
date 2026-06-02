import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Substring search across every target's OTHER_LDFLAGS.
///
/// Avoids the manual `grep project.pbxproj` step when diagnosing link-step regressions
/// like stray `-merge_framework` or `-Wl,-no_warn_duplicate_libraries` entries injected
/// by mergeable-library wiring.
public struct FindLinkFlagTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "find_link_flag",
            description:
                "Search every target's OTHER_LDFLAGS for a substring (e.g. '-merge_framework', '-no_warn_duplicate_libraries', '-rpath') and return each (target, configuration, matching element) hit. Reads pbxproj target-level values only — does not flatten xcconfig inheritance.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "flag": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Substring to search for inside OTHER_LDFLAGS entries (case-sensitive).",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Limit to a single configuration name. If omitted, all configurations are scanned.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("flag")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(flag) = arguments["flag"], !flag.isEmpty
        else {
            throw MCPError.invalidParams("project_path and flag are required")
        }

        let configFilter: String?
        if case let .string(c) = arguments["configuration"] { configFilter = c } else {
            configFilter = nil
        }

        do {
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            var hits: [String] = []
            for target in xcodeproj.pbxproj.nativeTargets.sorted(by: { $0.name < $1.name }) {
                guard let configList = target.buildConfigurationList else { continue }
                for config in configList.buildConfigurations.sorted(by: { $0.name < $1.name }) {
                    if let configFilter, config.name != configFilter { continue }
                    guard let raw = config.buildSettings["OTHER_LDFLAGS"] else { continue }
                    let elements: [String] = switch raw {
                        case let .string(s): [s]
                        case let .array(a): a
                    }
                    let matching = elements.filter { $0.contains(flag) }
                    if matching.isEmpty { continue }
                    for element in matching {
                        hits.append("  \(target.name) [\(config.name)] OTHER_LDFLAGS contains: \(element)")
                    }
                }
            }

            let header =
                "find_link_flag '\(flag)' in \(projectURL.lastPathComponent) (configuration=\(configFilter ?? "*")): \(hits.count) match\(hits.count == 1 ? "" : "es")"
            let body = hits.isEmpty ? "  (no matches)" : hits.joined(separator: "\n")

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
}
