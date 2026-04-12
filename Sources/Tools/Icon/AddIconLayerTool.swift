import MCP
import XCMCPCore
import Foundation

/// MCP tool for adding a layer to an existing Icon Composer `.icon` bundle.
public struct AddIconLayerTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "add_icon_layer",
            description:
            "Add a new image layer to an existing .icon bundle. "
                + "Copies the image into Assets/ and appends a layer entry to the specified group.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "image_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the image file (PNG, SVG, etc.)."),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Display name for the layer."),
                    ]),
                    "group_index": .object([
                        "type": .string("integer"),
                        "description": .string("Group to add the layer to (default: 0)."),
                    ]),
                    "create_group": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, create a new group for this layer instead of adding to an existing one."
                        ),
                    ]),
                    "scale": .object([
                        "type": .string("number"),
                        "description": .string("Scale factor for the layer (default: 1.0)."),
                    ]),
                    "offset_x": .object([
                        "type": .string("number"),
                        "description": .string("Horizontal offset in points (default: 0)."),
                    ]),
                    "offset_y": .object([
                        "type": .string("number"),
                        "description": .string("Vertical offset in points (default: 0)."),
                    ]),
                    "opacity": .object([
                        "type": .string("number"),
                        "description": .string("Layer opacity 0.0–1.0 (default: not set, full opacity)."),
                    ]),
                    "blend_mode": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Blend mode: normal, multiply, screen, overlay, etc. (default: not set)."
                        ),
                    ]),
                    "glass": .object([
                        "type": .string("boolean"),
                        "description": .string("Enable glass effect on this layer (default: true)."),
                    ]),
                ]),
                "required": .array([.string("bundle_path"), .string("image_path"), .string("name")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let imagePath = try arguments.getRequiredString("image_path")
        let name = try arguments.getRequiredString("name")
        let groupIndex = arguments.getInt("group_index") ?? 0
        let createGroup = arguments.getBool("create_group")
        let scale = arguments.getDouble("scale")
        let offsetX = arguments.getDouble("offset_x") ?? 0
        let offsetY = arguments.getDouble("offset_y") ?? 0
        let opacity = arguments.getDouble("opacity")
        let blendMode = arguments.getString("blend_mode")
        let glass = arguments["glass"] != nil ? arguments.getBool("glass") : true

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }
        guard FileManager.default.fileExists(atPath: imagePath) else {
            throw MCPError.invalidParams("Image file not found: \(imagePath)")
        }

        var manifest = try IconManifest.read(from: bundlePath)
        let imageFilename = URL(fileURLWithPath: imagePath).lastPathComponent

        // Copy image to Assets/
        let assetsDir = bundlePath + "/Assets"
        try FileManager.default.createDirectory(
            atPath: assetsDir, withIntermediateDirectories: true,
        )
        let destPath = assetsDir + "/" + imageFilename
        if FileManager.default.fileExists(atPath: destPath) {
            try FileManager.default.removeItem(atPath: destPath)
        }
        try FileManager.default.copyItem(atPath: imagePath, toPath: destPath)

        // Build position if non-default
        var position: IconManifest.Position?
        if let scale, scale != 1.0 {
            position = IconManifest.Position(scale: scale, translationInPoints: [offsetX, offsetY])
        } else if offsetX != 0 || offsetY != 0 {
            position = IconManifest.Position(scale: 1.0, translationInPoints: [offsetX, offsetY])
        }

        let layer = IconManifest.Layer(
            imageName: imageFilename,
            name: name,
            opacity: opacity,
            blendMode: blendMode,
            glass: glass,
            position: position,
        )

        if createGroup {
            let group = IconManifest.Group(
                layers: [layer],
                shadow: IconManifest.Shadow(),
                translucency: IconManifest.Translucency(),
            )
            manifest.groups.append(group)
        } else {
            guard groupIndex >= 0, groupIndex < manifest.groups.count else {
                throw MCPError.invalidParams(
                    "group_index \(groupIndex) out of range (0..<\(manifest.groups.count))"
                )
            }
            manifest.groups[groupIndex].layers.append(layer)
        }

        try manifest.write(to: bundlePath)

        let target = createGroup
            ? "new group \(manifest.groups.count - 1)"
            : "group \(groupIndex)"
        return CallTool.Result(
            content: [
                .text(
                    text: "Added layer \"\(name)\" (\(imageFilename)) to \(target)",
                    annotations: nil, _meta: nil,
                ),
            ],
        )
    }
}
