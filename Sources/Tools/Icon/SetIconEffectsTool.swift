import MCP
import XCMCPCore
import Foundation

/// MCP tool for configuring glass effects on an Icon Composer `.icon` bundle group.
///
/// Combines the functionality of `set_glass_effects` and `toggle_fx` from
/// [ethbak/icon-composer-mcp](https://github.com/ethbak/icon-composer-mcp).
public struct SetIconEffectsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "set_icon_effects",
            description:
            "Configure glass effects (specular, shadow, translucency, blur material, lighting) "
                + "on a .icon bundle group. All effect parameters are optional — only specified "
                + "values are changed.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "group_index": .object([
                        "type": .string("integer"),
                        "description": .string("Group index to modify (default: 0)."),
                    ]),
                    "specular": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable/disable specular highlights."),
                    ]),
                    "shadow_kind": .object([
                        "type": .string("string"),
                        "description": .string("Shadow type: 'neutral', 'layer-color', or 'none'."),
                    ]),
                    "shadow_opacity": .object([
                        "type": .string("number"),
                        "description": .string("Shadow opacity 0.0–1.0."),
                    ]),
                    "translucency_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable/disable translucency."),
                    ]),
                    "translucency_value": .object([
                        "type": .string("number"),
                        "description": .string("Translucency amount 0.0–1.0."),
                    ]),
                    "blur_material": .object([
                        "type": .string("number"),
                        "description": .string("Blur material amount 0.0–1.0 (set to -1 to clear)."),
                    ]),
                    "lighting": .object([
                        "type": .string("string"),
                        "description": .string("Lighting mode: 'combined' or 'individual'."),
                    ]),
                    "opacity": .object([
                        "type": .string("number"),
                        "description": .string("Group opacity 0.0–1.0."),
                    ]),
                    "blend_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Blend mode: normal, multiply, screen, overlay, etc."
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let groupIndex = arguments.getInt("group_index") ?? 0

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }

        var manifest = try IconManifest.read(from: bundlePath)
        guard groupIndex >= 0, groupIndex < manifest.groups.count else {
            throw MCPError.invalidParams(
                "group_index \(groupIndex) out of range (0..<\(manifest.groups.count))"
            )
        }

        var changes: [String] = []

        if arguments["specular"] != nil {
            manifest.groups[groupIndex].specular = arguments.getBool("specular")
            changes.append("specular=\(arguments.getBool("specular"))")
        }

        if let shadowKind = arguments.getString("shadow_kind") {
            if shadowKind == "none" {
                manifest.groups[groupIndex].shadow = nil
                changes.append("shadow=none")
            } else {
                let opacity = arguments.getDouble("shadow_opacity")
                    ?? manifest.groups[groupIndex].shadow?.opacity ?? 0.5
                manifest.groups[groupIndex].shadow = IconManifest.Shadow(
                    kind: shadowKind, opacity: opacity,
                )
                changes.append("shadow=\(shadowKind)/\(opacity)")
            }
        } else if let shadowOpacity = arguments.getDouble("shadow_opacity") {
            let kind = manifest.groups[groupIndex].shadow?.kind ?? "neutral"
            manifest.groups[groupIndex].shadow = IconManifest.Shadow(
                kind: kind, opacity: shadowOpacity,
            )
            changes.append("shadow_opacity=\(shadowOpacity)")
        }

        if arguments["translucency_enabled"] != nil || arguments["translucency_value"] != nil {
            let existing = manifest.groups[groupIndex].translucency
            let enabled = arguments["translucency_enabled"] != nil
                ? arguments.getBool("translucency_enabled")
                : (existing?.enabled ?? true)
            let value = arguments.getDouble("translucency_value")
                ?? existing?.value ?? 0.5
            manifest.groups[groupIndex].translucency = IconManifest.Translucency(
                enabled: enabled, value: value,
            )
            changes.append("translucency=\(enabled)/\(value)")
        }

        if let blur = arguments.getDouble("blur_material") {
            manifest.groups[groupIndex].blurMaterial = blur < 0 ? nil : blur
            changes.append("blur_material=\(blur < 0 ? "cleared" : "\(blur)")")
        }

        if let lighting = arguments.getString("lighting") {
            manifest.groups[groupIndex].lighting = lighting
            changes.append("lighting=\(lighting)")
        }

        if let opacity = arguments.getDouble("opacity") {
            manifest.groups[groupIndex].opacity = opacity
            changes.append("opacity=\(opacity)")
        }

        if let blendMode = arguments.getString("blend_mode") {
            manifest.groups[groupIndex].blendMode = blendMode
            changes.append("blend_mode=\(blendMode)")
        }

        try manifest.write(to: bundlePath)

        let desc = changes.isEmpty
            ? "No changes applied to group \(groupIndex)"
            : "Updated group \(groupIndex): \(changes.joined(separator: ", "))"
        return CallTool.Result(
            content: [.text(text: desc, annotations: nil, _meta: nil)],
        )
    }
}
