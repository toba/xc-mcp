import MCP
import XCMCPCore
import Foundation

/// Surfaces Xcode's on-disk PIF (Project Interchange Format) cache as JSON / a summary.
///
/// Used to diagnose duplicate-build-graph-node errors when the cause isn't visible in the
/// pbxproj — see `why_target_id` for the focused lookup.
public struct DumpPIFTool: Sendable {
    private let pathUtility: PathUtility
    private let reader: PIFCacheReader

    public init(pathUtility: PathUtility, reader: PIFCacheReader = PIFCacheReader()) {
        self.pathUtility = pathUtility
        self.reader = reader
    }

    public func tool() -> Tool {
        Tool(
            name: "dump_pif",
            description:
                "Dump Xcode's on-disk PIF (Project Interchange Format) build-graph cache for a "
                + "project. With no scope, returns a summary (workspaces, projects, target counts, "
                + "duplicate target guids). With scope=target/project/workspace and name=<name>, "
                + "returns the matching PIF JSON. Requires a prior build to populate the cache.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file."),
                    ]),
                    "scope": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("summary"),
                            .string("target"),
                            .string("project"),
                            .string("workspace"),
                        ]),
                        "description": .string(
                            "What to dump. 'summary' (default) lists everything at a glance.",
                        ),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target/project/workspace to dump. Required when scope is "
                            + "target/project/workspace. Matched case-insensitively against the "
                            + "PIF 'name' field.",
                        ),
                    ]),
                    "derived_data_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional override for the DerivedData project root. If omitted, the "
                            + "newest entry matching '<ProjectName>-*' under "
                            + "~/Library/Developer/Xcode/DerivedData is used.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }
        let scope = arguments["scope"]?.stringValue ?? "summary"
        let name = arguments["name"]?.stringValue
        let derivedDataPath = arguments["derived_data_path"]?.stringValue

        let resolved = try pathUtility.resolvePath(from: projectPath)

        let index: PIFCacheReader.Index
        do {
            index = try reader.load(
                projectPath: resolved,
                derivedDataPath: derivedDataPath,
            )
        } catch let error as PIFCacheReader.Error {
            throw MCPError.internalError(error.description)
        } catch {
            throw MCPError.internalError("Failed to load PIF cache: \(error)")
        }

        switch scope {
            case "summary":
                return .init(content: [.text(text: summary(index: index))])
            case "target":
                guard let name else {
                    throw MCPError.invalidParams("name is required when scope=target")
                }
                return try dumpTarget(name: name, index: index)
            case "project":
                guard let name else {
                    throw MCPError.invalidParams("name is required when scope=project")
                }
                return try dumpProject(name: name, index: index)
            case "workspace":
                guard let name else {
                    throw MCPError.invalidParams("name is required when scope=workspace")
                }
                return try dumpWorkspace(name: name, index: index)
            default:
                throw MCPError.invalidParams(
                    "scope must be summary|target|project|workspace, got '\(scope)'",
                )
        }
    }

    // MARK: - Summary

    private func summary(index: PIFCacheReader.Index) -> String {
        var lines: [String] = []
        lines.append("## PIF cache: \(index.cacheRoot)")
        if let date = index.newestEntryModified {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            lines.append("Newest entry: \(formatter.string(from: date))")
        }
        lines.append("")
        lines.append(
            "Workspaces: \(index.workspaces.count) | Projects: \(index.projects.count) | "
            + "Targets: \(index.targets.count)",
        )

        let duplicates = index.targetsByGuid.filter { $0.value.count > 1 }
        if !duplicates.isEmpty {
            lines.append("")
            lines.append(
                "### ⚠ Duplicate target guids (\(duplicates.count)) — likely "
                + "'Multiple targets in the build graph' culprits",
            )
            for (guid, hits) in duplicates.sorted(by: { $0.key < $1.key }) {
                let names = hits.map(\.name).joined(separator: ", ")
                lines.append("- \(guid) → \(hits.count)× (\(names))")
            }
        }

        if !index.workspaces.isEmpty {
            lines.append("")
            lines.append("### Workspaces")
            for w in index.workspaces {
                lines.append(
                    "- \(w.name ?? "<unnamed>") (guid=\(w.guid), \(w.projectRefs.count) projects)",
                )
            }
        }

        if !index.projects.isEmpty {
            lines.append("")
            lines.append("### Projects (\(index.projects.count))")
            for p in index.projects.sorted(by: { ($0.name ?? "") < ($1.name ?? "") }) {
                let label = p.name ?? p.path ?? p.guid
                lines.append("- \(label) (guid=\(p.guid), \(p.targetRefs.count) targets)")
            }
        }

        if !index.targets.isEmpty {
            lines.append("")
            lines.append("### Targets (\(index.targets.count))")
            for t in index.targets.sorted(by: { $0.name < $1.name }) {
                let type = t.productType.map { " [\($0)]" } ?? ""
                lines.append("- \(t.name)\(type) guid=\(t.guid)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Dump helpers

    private func dumpTarget(
        name: String, index: PIFCacheReader.Index,
    ) throws -> CallTool.Result {
        let lowered = name.lowercased()
        let matches = index.targets.filter { $0.name.lowercased() == lowered }
        if matches.isEmpty {
            return .init(content: [.text(text: "No PIF target named '\(name)'.")])
        }
        var sections: [String] = []
        for target in matches {
            let json = (try? reader.rawJSON(atPath: target.cacheFilePath)) ?? "<unavailable>"
            sections.append(
                "## Target '\(target.name)' (guid=\(target.guid))\n"
                + "File: \(target.cacheFileName)\n\n```json\n\(json)\n```",
            )
        }
        return .init(content: [.text(text: sections.joined(separator: "\n\n"))])
    }

    private func dumpProject(
        name: String, index: PIFCacheReader.Index,
    ) throws -> CallTool.Result {
        let lowered = name.lowercased()
        let matches = index.projects.filter {
            ($0.name ?? "").lowercased() == lowered
                || URL(fileURLWithPath: $0.path ?? "")
                    .deletingPathExtension()
                    .lastPathComponent.lowercased() == lowered
        }
        if matches.isEmpty {
            return .init(content: [.text(text: "No PIF project named '\(name)'.")])
        }
        var sections: [String] = []
        for project in matches {
            let json = (try? reader.rawJSON(atPath: project.cacheFilePath)) ?? "<unavailable>"
            sections.append(
                "## Project '\(project.name ?? "<unnamed>")' (guid=\(project.guid))\n"
                + "File: \(project.cacheFileName)\n\n```json\n\(json)\n```",
            )
        }
        return .init(content: [.text(text: sections.joined(separator: "\n\n"))])
    }

    private func dumpWorkspace(
        name: String, index: PIFCacheReader.Index,
    ) throws -> CallTool.Result {
        let lowered = name.lowercased()
        let matches = index.workspaces.filter { ($0.name ?? "").lowercased() == lowered }
        if matches.isEmpty {
            return .init(content: [.text(text: "No PIF workspace named '\(name)'.")])
        }
        var sections: [String] = []
        for ws in matches {
            let json = (try? reader.rawJSON(atPath: ws.cacheFilePath)) ?? "<unavailable>"
            sections.append(
                "## Workspace '\(ws.name ?? "<unnamed>")' (guid=\(ws.guid))\n"
                + "File: \(ws.cacheFileName)\n\n```json\n\(json)\n```",
            )
        }
        return .init(content: [.text(text: sections.joined(separator: "\n\n"))])
    }
}

private extension Value {
    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }
}
