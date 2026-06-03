import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct ListTargetsTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "list_targets",
            description: "List all targets in an Xcode project. Optional filters narrow the result to targets matching a product type, presence/absence of a PBXTargetDependency by name, or presence/absence of a build setting (with optional value substring match). When any filter is supplied, output includes each matched target's id, product type, and dependency names — use this for bulk audits (e.g. find every unit-test target lacking a dependency on ThesisApp; every framework target whose SUPPORTED_PLATFORMS is unset). Settings are read from pbxproj target-level buildSettings only — no xcconfig inheritance — and a setting is considered 'present' when any configuration defines it.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "product_type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only include targets with this productType (e.g. 'com.apple.product-type.bundle.unit-test', 'com.apple.product-type.framework'). Match is exact on rawValue.",
                        ),
                    ]),
                    "has_dependency": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only include targets whose PBXTargetDependency list contains a dependency resolving to this target name (dep.name, dep.target.name, or dep.product.productName).",
                        ),
                    ]),
                    "missing_dependency": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only include targets whose PBXTargetDependency list does NOT contain a dependency resolving to this target name. Use to find targets that should have a dep but don't.",
                        ),
                    ]),
                    "has_setting": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "value": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("name")]),
                        "description": .string(
                            "Only include targets that define this build setting in at least one configuration. If 'value' is provided, the setting's value (or any element if array-typed) must contain it as a substring (case-sensitive).",
                        ),
                    ]),
                    "missing_setting": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only include targets that do NOT define this build setting in any configuration. Use to find targets where e.g. SUPPORTED_PLATFORMS or MERGEABLE_LIBRARY is unset.",
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

        let productTypeFilter: String? = stringArg(arguments["product_type"])
        let hasDependency: String? = stringArg(arguments["has_dependency"])
        let missingDependency: String? = stringArg(arguments["missing_dependency"])
        let missingSetting: String? = stringArg(arguments["missing_setting"])

        let hasSetting: (name: String, value: String?)?
        if case let .object(obj) = arguments["has_setting"] {
            guard case let .string(name) = obj["name"] else {
                throw MCPError.invalidParams("has_setting.name is required when has_setting is provided")
            }
            let value: String? = stringArg(obj["value"])
            hasSetting = (name, value)
        } else {
            hasSetting = nil
        }

        let anyFilter = productTypeFilter != nil
            || hasDependency != nil
            || missingDependency != nil
            || missingSetting != nil
            || hasSetting != nil

        do {
            let resolvedPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))
            let targets = xcodeproj.pbxproj.nativeTargets.sorted(by: { $0.name < $1.name })

            var lines: [String] = []
            var matched = 0

            for target in targets {
                let productType = target.productType?.rawValue ?? "unknown"
                if let productTypeFilter, productType != productTypeFilter { continue }

                let depNames: [String] = target.dependencies.map { dep in
                    dep.name ?? dep.target?.name ?? dep.product?.productName ?? "<unnamed>"
                }

                if let hasDependency, !depNames.contains(hasDependency) { continue }
                if let missingDependency, depNames.contains(missingDependency) { continue }

                if let hasSetting {
                    let present = settingPresent(
                        target: target, name: hasSetting.name, valueSubstring: hasSetting.value,
                    )
                    if !present { continue }
                }
                if let missingSetting {
                    let present = settingPresent(
                        target: target, name: missingSetting, valueSubstring: nil,
                    )
                    if present { continue }
                }

                matched += 1
                if anyFilter {
                    let deps = depNames.isEmpty ? "<none>" : depNames.joined(separator: ", ")
                    lines.append(
                        "- \(target.name) [id=\(target.uuid) productType=\(productType) dependencies=[\(deps)]]",
                    )
                } else {
                    lines.append("- \(target.name) (\(productType))")
                }
            }

            let header: String
            if anyFilter {
                var filters: [String] = []
                if let productTypeFilter { filters.append("product_type=\(productTypeFilter)") }
                if let hasDependency { filters.append("has_dependency=\(hasDependency)") }
                if let missingDependency { filters.append("missing_dependency=\(missingDependency)") }
                if let hasSetting {
                    let v = hasSetting.value.map { "~\($0)" } ?? ""
                    filters.append("has_setting=\(hasSetting.name)\(v)")
                }
                if let missingSetting { filters.append("missing_setting=\(missingSetting)") }
                header =
                    "Targets in \(projectURL.lastPathComponent) (\(filters.joined(separator: ", "))): \(matched) match\(matched == 1 ? "" : "es")"
            } else {
                header = "Targets in \(projectURL.lastPathComponent):"
            }

            let body: String
            if lines.isEmpty {
                body = anyFilter ? "  (no matches)" : "No targets found in the project."
            } else {
                body = lines.joined(separator: "\n")
            }

            let text = anyFilter ? "\(header)\n\(body)" : "\(header)\n\(body)"

            return CallTool.Result(
                content: [.text(text: text, annotations: nil, _meta: nil)],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to read Xcode project: \(error.localizedDescription)",
            )
        }
    }

    private func stringArg(_ v: Value?) -> String? {
        if case let .string(s) = v, !s.isEmpty { return s }
        return nil
    }

    private func settingPresent(
        target: PBXNativeTarget, name: String, valueSubstring: String?,
    ) -> Bool {
        guard let configList = target.buildConfigurationList else { return false }
        for config in configList.buildConfigurations {
            guard let raw = config.buildSettings[name] else { continue }
            guard let needle = valueSubstring else { return true }
            switch raw {
                case let .string(s): if s.contains(needle) { return true }
                case let .array(arr): if arr.contains(where: { $0.contains(needle) }) { return true }
            }
        }
        return false
    }
}
