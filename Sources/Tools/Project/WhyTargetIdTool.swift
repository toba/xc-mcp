import MCP
import XCMCPCore
import Foundation

/// Resolves a target-ID hash from a "Multiple targets in the build graph" error to the
/// concrete PIF target(s) that produced it.
public struct WhyTargetIdTool: Sendable {
    private let pathUtility: PathUtility
    private let reader: PIFCacheReader

    public init(pathUtility: PathUtility, reader: PIFCacheReader = PIFCacheReader()) {
        self.pathUtility = pathUtility
        self.reader = reader
    }

    public func tool() -> Tool {
        Tool(
            name: "why_target_id",
            description:
                "Look up the target-ID hash from a 'Multiple targets in the build graph have the "
                + "target ID …' error and report which PIF target(s) carry that guid, which "
                + "project(s) declare them, and which other targets depend on that guid. When >1 "
                + "target matches, those are the colliding build-graph nodes. Reads the on-disk "
                + "PIF cache; requires a prior build.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file."),
                    ]),
                    "target_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Either the raw 64-char target guid or the full "
                            + "'target-<Name>-<hash>-SDKROOT:<sdk>:SDK_VARIANT:<sdk>' string "
                            + "copied from the error message.",
                        ),
                    ]),
                    "derived_data_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional DerivedData project-root override (e.g. "
                            + "'.../DerivedData/Thesis-<hash>'). Defaults to the newest "
                            + "'<ProjectName>-*' directory.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("target_id")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetID) = arguments["target_id"]
        else {
            throw MCPError.invalidParams("project_path and target_id are required")
        }
        let derivedDataPath = arguments["derived_data_path"].flatMap {
            if case let .string(s) = $0 { return s }
            return String?.none
        }

        guard let guid = PIFCacheReader.extractGuid(from: targetID) else {
            throw MCPError.invalidParams(
                "Could not find a 64-char hex target guid in '\(targetID)'. Pass the raw guid "
                + "or the full target-<Name>-<hash>-SDKROOT:… string.",
            )
        }

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

        let matches = index.targetsByGuid[guid] ?? []

        var lines: [String] = []
        lines.append("## why_target_id: \(guid)")
        if guid != targetID {
            lines.append("(extracted from '\(targetID)')")
        }
        lines.append("")
        lines.append("PIF cache: \(index.cacheRoot)")
        lines.append("")

        if matches.isEmpty {
            lines.append(
                "No PIF target carries this guid. The cache may be stale — rebuild the project "
                + "and try again.",
            )
            return .init(content: [.text(text: lines.joined(separator: "\n"))])
        }

        if matches.count == 1 {
            lines.append("### Single match (no collision)")
        } else {
            lines.append(
                "### ⚠ \(matches.count) targets share this guid — this is the duplicate "
                + "build-graph node",
            )
        }
        lines.append("")

        for (i, target) in matches.enumerated() {
            lines.append("**Match #\(i + 1): \(target.name)**")
            if let type = target.productType {
                lines.append("- productType: \(type)")
            }
            if let product = target.productReferenceName {
                lines.append("- product: \(product)")
            }
            lines.append("- cacheFile: \(target.cacheFileName)")

            let owners = index.projectsByTargetRef[target.cacheFileNameStem] ?? []
            if !owners.isEmpty {
                for owner in owners {
                    let label = owner.name ?? owner.path ?? owner.guid
                    lines.append("- project: \(label) (guid=\(owner.guid))")
                    if let path = owner.path {
                        lines.append("  path: \(path)")
                    }
                }
            } else {
                lines.append("- project: <not listed by any PIF project — orphaned?>")
            }

            if !target.dependencies.isEmpty {
                lines.append("- dependencies (\(target.dependencies.count)):")
                for dep in target.dependencies {
                    lines.append("  - \(dep.name ?? "<unnamed>") guid=\(dep.guid)")
                }
            }
            lines.append("")
        }

        // Show every target that depends on this guid — useful for tracing who pulled it in.
        let consumers = index.targets.filter { candidate in
            candidate.dependencies.contains(where: { $0.guid == guid })
        }
        if !consumers.isEmpty {
            lines.append("### Consumers (targets that depend on this guid)")
            for consumer in consumers.sorted(by: { $0.name < $1.name }) {
                lines.append("- \(consumer.name) (guid=\(consumer.guid))")
            }
        }

        return .init(content: [.text(text: lines.joined(separator: "\n"))])
    }
}

private extension PIFCacheReader.Target {
    /// Cache files end in "-json"; the project's `targets` array stores the stem without it.
    var cacheFileNameStem: String {
        cacheFileName.hasSuffix("-json")
            ? String(cacheFileName.dropLast(5))
            : cacheFileName
    }
}
