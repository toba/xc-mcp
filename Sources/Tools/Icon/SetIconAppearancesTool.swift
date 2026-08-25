import MCP
import XCMCPCore
import Foundation

/// MCP tool for configuring dark/tinted mode overrides in an Icon Composer `.icon` bundle.
public struct SetIconAppearancesTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "set_icon_appearances",
            description:
                "Apply dark or tinted mode overrides to a .icon bundle's fill, group, or layer. "
                + "Creates appearance specializations for adaptive icon rendering.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string(
                            "What to override: 'fill' (background), 'group', or 'layer'."
                        ),
                    ]),
                    "appearance": .object([
                        "type": .string("string"),
                        "description": .string("Appearance mode: 'dark' or 'tinted'."),
                    ]),
                    "group_index": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Group index (default: 0, for group/layer targets)."),
                    ]),
                    "layer_index": .object([
                        "type": .string("integer"),
                        "description": .string("Layer index (required when target is 'layer')."),
                    ]),
                    "bg_color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Background fill color for this appearance (hex or Apple notation). "
                                + "Used with target 'fill'."
                        ),
                    ]),
                    "hidden": .object([
                        "type": .string("boolean"),
                        "description": .string("Hide this group/layer in this appearance."),
                    ]),
                    "opacity": .object([
                        "type": .string("number"),
                        "description": .string("Override opacity for this appearance."),
                    ]),
                    "fill_color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Layer fill color for this appearance (hex or Apple notation)."
                        ),
                    ]),
                    "scale": .object([
                        "type": .string("number"),
                        "description": .string("Override scale for this appearance."),
                    ]),
                    "offset_x": .object([
                        "type": .string("number"),
                        "description": .string("Override horizontal offset."),
                    ]),
                    "offset_y": .object([
                        "type": .string("number"),
                        "description": .string("Override vertical offset."),
                    ]),
                ]),
                "required": .array([
                    .string("bundle_path"), .string("target"), .string("appearance"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let target = try arguments.getRequiredString("target")
        let appearance = try arguments.getRequiredString("appearance")

        guard appearance == "dark" || appearance == "tinted" else {
            throw MCPError.invalidParams("appearance must be 'dark' or 'tinted'")
        }

        var manifest = try IconManifest.open(bundlePath)
        let desc: String

        switch target {
            case "fill":
                guard let bgColor = arguments.getString("bg_color") else {
                    throw MCPError.invalidParams(
                        "bg_color is required for fill appearance override")
                }
                let fillValue = IconManifest.resolveFill(bgColor)
                let spec = IconManifest.Specialization(appearance: appearance, value: fillValue)

                var specs = manifest.fillSpecializations ?? []
                specs.removeAll { $0.appearance == appearance }
                specs.append(spec)
                manifest.fillSpecializations = specs
                desc = "Set \(appearance) fill to \(bgColor)"

            case "group", "layer":
                // group and layer specializations need direct manifest editing, so return before
                // the write rather than rewrite an unchanged manifest
                return CallTool.Result.text(
                    """
                    Appearance specializations for \(target) require direct manifest editing. \
                    Use read_icon with set_icon_fill or set_icon_effects.
                    """)

            default: throw MCPError.invalidParams("target must be 'fill', 'group', or 'layer'")
        }

        try manifest.write(to: bundlePath)

        return CallTool.Result.text(desc)
    }
}
