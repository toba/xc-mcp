import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// MCP tool for creating an Icon Composer `.icon` bundle from a PNG image.
///
/// Creates the `.icon` directory structure with an `icon.json` manifest and
/// copies the source PNG into the `Assets/` subdirectory. Optionally adds the
/// `.icon` to an Xcode project with the correct `lastKnownFileType`.
public struct CreateIconTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "create_icon",
            description:
            "Create an Icon Composer .icon bundle from a PNG image. "
                + "Generates the icon.json manifest and Assets/ directory structure "
                + "compatible with Icon Composer and ictool. "
                + "Optionally adds the .icon file to an Xcode project with the correct "
                + "lastKnownFileType (folder.iconcomposer.icon) and wires it into the "
                + "Resources build phase.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "png_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the source PNG image."
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path for the output .icon bundle (e.g. 'AppIcon.icon'). "
                                + "Must end with .icon extension."
                        ),
                    ]),
                    "layer_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Display name for the image layer (default: derived from PNG filename)."
                        ),
                    ]),
                    "fill_color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Background fill color — hex (e.g. '#FF8800') or Apple color notation "
                                + "(e.g. 'extended-srgb:0.0,0.5,1.0,1.0'). Default: no fill."
                        ),
                    ]),
                    "dark_fill_color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Dark mode background fill (hex or Apple notation). "
                                + "When set, creates a fill-specialization for dark appearance."
                        ),
                    ]),
                    "glyph_scale": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Scale factor for the image layer (default: 1.0, range: 0.1–2.0)."
                        ),
                    ]),
                    "glass": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Enable glass effect on the image layer (default: false)."
                        ),
                    ]),
                    "specular": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Enable specular highlights on the group (default: not set)."
                        ),
                    ]),
                    "shadow_kind": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Shadow type: 'neutral' (default), 'layer-color', or 'none'."
                        ),
                    ]),
                    "shadow_opacity": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Shadow opacity 0.0–1.0 (default: 0.5)."
                        ),
                    ]),
                    "translucency_enabled": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Enable translucency effect (default: true)."
                        ),
                    ]),
                    "translucency_value": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Translucency amount 0.0–1.0 (default: 0.5)."
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to .xcodeproj to add the .icon file to (optional)."
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target to wire the .icon into (optional, requires project_path)."
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Group to add the .icon to (optional, requires project_path)."
                        ),
                    ]),
                ]),
                "required": .array([.string("png_path"), .string("output_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let pngPath = try arguments.getRequiredString("png_path")
        let outputPath = try arguments.getRequiredString("output_path")
        let layerName = arguments.getString("layer_name")
        let fillColor = arguments.getString("fill_color")
        let darkFillColor = arguments.getString("dark_fill_color")
        let glyphScale = arguments.getDouble("glyph_scale")
        let glass = arguments.getBool("glass")
        let specular: Bool? = arguments["specular"] != nil ? arguments.getBool("specular") : nil
        let shadowKind = arguments.getString("shadow_kind") ?? "neutral"
        let shadowOpacity = arguments.getDouble("shadow_opacity") ?? 0.5
        let translucencyEnabled = arguments["translucency_enabled"] != nil
            ? arguments.getBool("translucency_enabled") : true
        let translucencyValue = arguments.getDouble("translucency_value") ?? 0.5
        let projectPath = arguments.getString("project_path")
        let targetName = arguments.getString("target_name")
        let groupName = arguments.getString("group_name")

        guard outputPath.hasSuffix(".icon") else {
            throw MCPError.invalidParams("output_path must end with .icon")
        }

        let resolvedPNG = try pathUtility.resolvePath(from: pngPath)
        let resolvedOutput = try pathUtility.resolvePath(from: outputPath)

        guard FileManager.default.fileExists(atPath: resolvedPNG) else {
            throw MCPError.invalidParams("PNG file not found: \(resolvedPNG)")
        }

        let fm = FileManager.default
        let pngFilename = URL(fileURLWithPath: resolvedPNG).lastPathComponent
        let pngBasename = URL(fileURLWithPath: resolvedPNG)
            .deletingPathExtension().lastPathComponent
        let effectiveLayerName = layerName ?? pngBasename

        // Create .icon bundle structure
        let assetsDir = resolvedOutput + "/Assets"
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

        // Copy PNG into Assets/
        let destPNG = assetsDir + "/" + pngFilename
        if fm.fileExists(atPath: destPNG) {
            try fm.removeItem(atPath: destPNG)
        }
        try fm.copyItem(atPath: resolvedPNG, toPath: destPNG)

        // Build layer
        var position: IconManifest.Position?
        if let glyphScale, glyphScale != 1.0 {
            position = IconManifest.Position(scale: glyphScale)
        }

        let layer = IconManifest.Layer(
            imageName: pngFilename,
            name: effectiveLayerName,
            glass: glass ? true : false,
            position: position,
        )

        // Build group
        let shadow = shadowKind == "none"
            ? nil
            : IconManifest.Shadow(kind: shadowKind, opacity: shadowOpacity)
        let translucency = IconManifest.Translucency(
            enabled: translucencyEnabled, value: translucencyValue,
        )

        let group = IconManifest.Group(
            layers: [layer],
            shadow: shadow,
            specular: specular,
            translucency: translucency,
        )

        // Build fill
        let resolvedFill = fillColor.map { Self.resolveFill($0) }

        // Dark mode specialization
        var fillSpecializations: [IconManifest.Specialization<IconManifest.Fill>]?
        if let darkFillColor {
            fillSpecializations = [
                IconManifest.Specialization(
                    appearance: "dark",
                    value: Self.resolveFill(darkFillColor)
                ),
            ]
        }

        let manifest = IconManifest(
            groups: [group],
            fill: resolvedFill,
            fillSpecializations: fillSpecializations,
        )

        try manifest.write(to: resolvedOutput)

        let bundleName = URL(fileURLWithPath: resolvedOutput).lastPathComponent
        var messages = ["Created \(bundleName) with \(pngFilename)"]

        // Optionally add to Xcode project
        if let projectPath {
            let addFileTool = AddFileTool(pathUtility: pathUtility)
            var addArgs: [String: Value] = [
                "project_path": .string(projectPath),
                "file_path": .string(resolvedOutput),
            ]
            if let targetName {
                addArgs["target_name"] = .string(targetName)
            }
            if let groupName {
                addArgs["group_name"] = .string(groupName)
            }
            let addResult = try addFileTool.execute(arguments: addArgs)
            if case let .text(text, _, _) = addResult.content.first {
                messages.append(text)
            }
        }

        return CallTool.Result(
            content: [
                .text(
                    text: messages.joined(separator: "\n"),
                    annotations: nil,
                    _meta: nil,
                ),
            ],
        )
    }

    /// Resolves a fill color string — hex colors are converted to Apple sRGB notation.
    private static func resolveFill(_ color: String) -> IconManifest.Fill {
        if color.hasPrefix("#") || (color.count == 6 && color.allSatisfy(\.isHexDigit)) {
            return .fromHex(color)
        }
        // Already in Apple notation (e.g. "extended-srgb:0.0,0.5,1.0,1.0")
        return .automaticGradient(color)
    }
}
