import MCP
import XCMCPCore
import Foundation

/// MCP tool for removing a layer or group from an Icon Composer `.icon` bundle.
public struct RemoveIconLayerTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "remove_icon_layer",
            description:
            "Remove a layer or entire group from a .icon bundle. "
                + "Optionally purges unreferenced asset files from the Assets/ directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "description": .string("What to remove: 'layer' or 'group'."),
                    ]),
                    "group_index": .object([
                        "type": .string("integer"),
                        "description": .string("Index of the group (default: 0)."),
                    ]),
                    "layer_index": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Index of the layer within the group (required when target is 'layer')."
                        ),
                    ]),
                    "purge_assets": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Remove asset files no longer referenced by any layer (default: true)."
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_path"), .string("target"), .string("group_index")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let target = try arguments.getRequiredString("target")
        let groupIndex = arguments.getInt("group_index") ?? 0
        let layerIndex = arguments.getInt("layer_index")
        let purgeAssets = arguments["purge_assets"] != nil ? arguments.getBool("purge_assets") : true

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }

        var manifest = try IconManifest.read(from: bundlePath)
        guard groupIndex >= 0, groupIndex < manifest.groups.count else {
            throw MCPError.invalidParams(
                "group_index \(groupIndex) out of range (0..<\(manifest.groups.count))"
            )
        }

        var removedDescription: String

        switch target {
        case "group":
            let group = manifest.groups[groupIndex]
            let layerNames = group.layers.map(\.name).joined(separator: ", ")
            manifest.groups.remove(at: groupIndex)
            removedDescription = "group \(groupIndex) (layers: \(layerNames))"

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
            let layer = layers[layerIndex]
            manifest.groups[groupIndex].layers.remove(at: layerIndex)
            removedDescription = "layer \(layerIndex) \"\(layer.name)\" from group \(groupIndex)"

        default:
            throw MCPError.invalidParams("target must be 'layer' or 'group'")
        }

        try manifest.write(to: bundlePath)

        // Purge unreferenced assets
        var purged: [String] = []
        if purgeAssets {
            let referenced = manifest.referencedAssets
            let onDisk = IconManifest.listAssets(in: bundlePath)
            for asset in onDisk where !referenced.contains(asset) {
                try IconManifest.removeAsset(asset, from: bundlePath)
                purged.append(asset)
            }
        }

        var message = "Removed \(removedDescription)"
        if !purged.isEmpty {
            message += "\nPurged unreferenced assets: \(purged.joined(separator: ", "))"
        }

        return CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
        )
    }
}
