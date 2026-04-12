import MCP
import XCMCPCore
import Foundation

/// MCP tool for inspecting an Icon Composer `.icon` bundle.
///
/// Reads and formats the `icon.json` manifest and lists asset files.
public struct ReadIconTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "read_icon",
            description:
            "Inspect an Icon Composer .icon bundle. "
                + "Returns the icon.json manifest contents, asset file list, "
                + "and a human-readable summary of groups, layers, fill, and effects.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                ]),
                "required": .array([.string("bundle_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }

        let manifest = try IconManifest.read(from: bundlePath)
        let assets = IconManifest.listAssets(in: bundlePath)

        var lines: [String] = []
        let bundleName = URL(fileURLWithPath: bundlePath).lastPathComponent
        lines.append("# \(bundleName)")
        lines.append("")

        // Fill
        if let fill = manifest.fill {
            lines.append("**Fill:** \(describeFill(fill))")
        }
        if let specs = manifest.fillSpecializations, !specs.isEmpty {
            for spec in specs {
                let appearance = spec.appearance ?? spec.idiom ?? "unknown"
                lines.append("**Fill (\(appearance)):** \(describeFill(spec.value))")
            }
        }

        // Groups and layers
        for (gi, group) in manifest.groups.enumerated() {
            lines.append("")
            lines.append("## Group \(gi)")

            if let shadow = group.shadow {
                lines.append("  Shadow: \(shadow.kind), opacity \(shadow.opacity)")
            }
            if let translucency = group.translucency {
                lines.append(
                    "  Translucency: \(translucency.enabled ? "on" : "off"), value \(translucency.value)"
                )
            }
            if let specular = group.specular {
                lines.append("  Specular: \(specular)")
            }
            if let blur = group.blurMaterial {
                lines.append("  Blur material: \(blur)")
            }
            if let lighting = group.lighting {
                lines.append("  Lighting: \(lighting)")
            }

            for (li, layer) in group.layers.enumerated() {
                var desc = "  Layer \(li): \"\(layer.name)\" → \(layer.imageName)"
                if layer.glass == true { desc += " [glass]" }
                if layer.hidden == true { desc += " [hidden]" }
                if let pos = layer.position {
                    desc += " scale=\(pos.scale)"
                    if pos.translationInPoints != [0, 0] {
                        desc += " offset=\(pos.translationInPoints)"
                    }
                }
                if let opacity = layer.opacity { desc += " opacity=\(opacity)" }
                if let blend = layer.blendMode { desc += " blend=\(blend)" }
                lines.append(desc)
            }
        }

        // Platforms
        lines.append("")
        lines.append("**Platforms:**")
        if let squares = manifest.supportedPlatforms.squares {
            switch squares {
            case .shared:
                lines.append("  Squares: shared (iOS, macOS, visionOS)")
            case let .platforms(list):
                lines.append("  Squares: \(list.joined(separator: ", "))")
            }
        }
        if let circles = manifest.supportedPlatforms.circles {
            lines.append("  Circles: \(circles.joined(separator: ", "))")
        }

        // Assets
        lines.append("")
        lines.append("**Assets (\(assets.count)):** \(assets.joined(separator: ", "))")

        // Raw JSON
        lines.append("")
        lines.append("```json")
        let jsonData = try manifest.jsonData()
        lines.append(String(data: jsonData, encoding: .utf8) ?? "{}")
        lines.append("```")

        return CallTool.Result(
            content: [.text(text: lines.joined(separator: "\n"), annotations: nil, _meta: nil)],
        )
    }

    private func describeFill(_ fill: IconManifest.Fill) -> String {
        switch fill {
        case let .solid(color): return "solid \(color)"
        case let .automaticGradient(color): return "automatic-gradient \(color)"
        case let .linearGradient(colors, _): return "linear-gradient \(colors.joined(separator: " → "))"
        }
    }
}
