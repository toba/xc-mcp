import MCP
import XCMCPCore
import Foundation

/// MCP tool for modifying the background fill of an Icon Composer `.icon` bundle.
public struct SetIconFillTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "set_icon_fill",
            description:
                "Set the background fill of a .icon bundle. "
                + "Supports solid color, automatic gradient, linear gradient, or clearing the fill. "
                + "Accepts hex colors (#FF8800) or Apple color notation (srgb:R,G,B,A).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon bundle."),
                    ]),
                    "type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Fill type: 'solid', 'automatic' (gradient from single color), "
                                + "'gradient' (two-color linear), or 'none' to clear."
                        ),
                    ]),
                    "color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Primary color — hex (#FF8800) or Apple notation (srgb:R,G,B,A)."
                        ),
                    ]),
                    "color2": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Second color for linear gradient (required when type is 'gradient')."
                        ),
                    ]),
                    "gradient_angle": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Gradient angle in degrees, 0 = top-to-bottom (default: 0). "
                                + "Only used with type 'gradient'."
                        ),
                    ]),
                ]),
                "required": .array([.string("bundle_path"), .string("type")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        let bundlePath = try arguments.getRequiredString("bundle_path")
        let fillType = try arguments.getRequiredString("type")
        let color = arguments.getString("color")
        let color2 = arguments.getString("color2")
        let gradientAngle = arguments.getDouble("gradient_angle") ?? 0

        guard FileManager.default.fileExists(atPath: bundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(bundlePath)")
        }

        var manifest = try IconManifest.read(from: bundlePath)

        switch fillType {
            case "none":
                manifest.fill = nil
                manifest.fillSpecializations = nil

            case "solid":
                guard let color else {
                    throw MCPError.invalidParams("color is required for solid fill")
                }
                manifest.fill = .solid(resolveColor(color))

            case "automatic":
                guard let color else {
                    throw MCPError.invalidParams("color is required for automatic fill")
                }
                manifest.fill = .automaticGradient(resolveColor(color))

            case "gradient":
                guard let color, let color2 else {
                    throw MCPError.invalidParams("color and color2 are required for gradient fill")
                }
                let angleRad = gradientAngle * .pi / 180
                let orientation = IconManifest.GradientOrientation(
                    start: IconManifest.Point(
                        x: 0.5 - sin(angleRad) * 0.5, y: 0.5 - cos(angleRad) * 0.5),
                    stop: IconManifest.Point(
                        x: 0.5 + sin(angleRad) * 0.5, y: 0.5 + cos(angleRad) * 0.5),
                )
                manifest.fill = .linearGradient(
                    [resolveColor(color), resolveColor(color2)],
                    orientation: orientation,
                )

            default:
                throw MCPError.invalidParams(
                    "type must be 'solid', 'automatic', 'gradient', or 'none'")
        }

        try manifest.write(to: bundlePath)

        let desc = fillType == "none" ? "Cleared fill" : "Set fill to \(fillType)"
        return CallTool.Result(
            content: [.text(text: desc, annotations: nil, _meta: nil)],
        )
    }

    private func resolveColor(_ color: String) -> String {
        color.hasPrefix("#") || (color.count == 6 && color.allSatisfy(\.isHexDigit))
            ? IconManifest.hexToSRGB(color)
            : color
    }
}
