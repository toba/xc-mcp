import MCP
import XCMCPCore
import Foundation

/// MCP tool for adjusting layer or group position/scale in an Icon Composer `.icon` bundle.
public struct SetIconLayerPositionTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "set_icon_layer_position",
            description:
                "Adjust the scale and offset of a layer or group in a .icon bundle.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string("What to position: 'layer' (default) or 'group'."),
                    ]),
                    "group_index": .object([
                        "type": .string("integer"),
                        "description": .string("Group index (default: 0)."),
                    ]),
                    "layer_index": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Layer index within the group (required when target is 'layer')."
                        ),
                    ]),
                    "scale": .object([
                        "type": .string("number"),
                        "description": .string("Scale factor (e.g. 0.75 for 75%)."),
                    ]),
                    "offset_x": .object([
                        "type": .string("number"),
                        "description": .string("Horizontal offset in points."),
                    ]),
                    "offset_y": .object([
                        "type": .string("number"),
                        "description": .string("Vertical offset in points."),
                    ]),
                ]),
                "required": .array([.string("bundle_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let target = arguments.getString("target") ?? "layer"
        let groupIndex = arguments.getInt("group_index") ?? 0
        let layerIndex = arguments.getInt("layer_index")
        let scale = arguments.getDouble("scale")
        let offsetX = arguments.getDouble("offset_x")
        let offsetY = arguments.getDouble("offset_y")

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }

        var manifest = try IconManifest.read(from: bundlePath)
        guard groupIndex >= 0, groupIndex < manifest.groups.count else {
            throw MCPError.invalidParams(
                "group_index \(groupIndex) out of range (0..<\(manifest.groups.count))"
            )
        }

        // Read existing or create new position
        let desc: String

        switch target {
            case "group":
                let existing = manifest.groups[groupIndex].position
                let newScale = scale ?? existing?.scale ?? 1.0
                let newOffsetX = offsetX ?? existing?.translationInPoints.first ?? 0
                let newOffsetY = offsetY
                    ?? (existing?.translationInPoints.count ?? 0 > 1
                        ? existing!.translationInPoints[1]
                        : 0)
                manifest.groups[groupIndex].position = IconManifest.Position(
                    scale: newScale, translationInPoints: [newOffsetX, newOffsetY],
                )
                desc =
                    "group \(groupIndex) → scale=\(newScale), offset=[\(newOffsetX), \(newOffsetY)]"

            case "layer":
                guard let layerIndex else {
                    throw MCPError.invalidParams("layer_index is required when target is 'layer'")
                }
                let layers = manifest.groups[groupIndex].layers
                guard layerIndex >= 0, layerIndex < layers.count else {
                    throw MCPError.invalidParams(
                        "layer_index \(layerIndex) out of range (0..<\(layers.count))"
                    )
                }
                let existing = manifest.groups[groupIndex].layers[layerIndex].position
                let newScale = scale ?? existing?.scale ?? 1.0
                let newOffsetX = offsetX ?? existing?.translationInPoints.first ?? 0
                let newOffsetY = offsetY
                    ?? (existing?.translationInPoints.count ?? 0 > 1
                        ? existing!.translationInPoints[1]
                        : 0)
                manifest.groups[groupIndex].layers[layerIndex].position = IconManifest.Position(
                    scale: newScale, translationInPoints: [newOffsetX, newOffsetY],
                )
                desc = "layer \(layerIndex) in group \(groupIndex) → scale=\(newScale), offset=[\(newOffsetX), \(newOffsetY)]"

            default: throw MCPError.invalidParams("target must be 'layer' or 'group'")
        }

        try manifest.write(to: bundlePath)

        return CallTool.Result(
            content: [.text(text: "Positioned \(desc)", annotations: nil, _meta: nil)],
        )
    }
}
