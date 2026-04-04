import MCP
import XCMCPCore
import Foundation

public struct ExportIconTool: Sendable {
    private static let ictoolSearchPaths = [
        "/Applications/Icon Composer.app/Contents/Executables/ictool",
        "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool",
        "/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool",
    ]

    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "export_icon",
            description:
            "Export an .icon file (Icon Composer format) to PNG using ictool. "
                + "Renders at the specified size, platform, and rendition (Default, Tinted, TintedDark, etc.). "
                + "Requires Icon Composer (standalone or bundled with Xcode 26+).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "icon_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .icon file."),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string("Output PNG file path."),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Target platform: macOS (default), iOS, watchOS, visionOS.",
                        ),
                    ]),
                    "rendition": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Rendition style: Default (default), Tinted, TintedDark, Automatic, AutomaticDark, AutomaticTinted.",
                        ),
                    ]),
                    "width": .object([
                        "type": .string("integer"),
                        "description": .string("Width in points (default 1024)."),
                    ]),
                    "height": .object([
                        "type": .string("integer"),
                        "description": .string("Height in points (default 1024)."),
                    ]),
                    "scale": .object([
                        "type": .string("integer"),
                        "description": .string("Scale factor (default 1)."),
                    ]),
                    "light_angle": .object([
                        "type": .string("number"),
                        "description": .string("Light angle for rendering (optional)."),
                    ]),
                    "tint_color": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Tint color hue value 0.0-1.0 (optional, for Tinted/TintedDark renditions).",
                        ),
                    ]),
                    "tint_strength": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Tint strength 0.0-1.0 (optional, for Tinted/TintedDark renditions).",
                        ),
                    ]),
                ]),
                "required": .array([.string("icon_path"), .string("output_path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let iconPath = try arguments.getRequiredString("icon_path")
        let outputPath = try arguments.getRequiredString("output_path")
        let platform = arguments.getString("platform") ?? "macOS"
        let rendition = arguments.getString("rendition") ?? "Default"
        let width = arguments.getInt("width") ?? 1024
        let height = arguments.getInt("height") ?? 1024
        let scale = arguments.getInt("scale") ?? 1

        // Find ictool
        guard
            let ictoolPath = Self.ictoolSearchPaths.first(where: {
                FileManager.default.fileExists(atPath: $0)
            })
        else {
            throw MCPError.internalError(
                "ictool not found. Install Icon Composer from developer.apple.com/download or use Xcode 26+.",
            )
        }

        // Validate input file exists
        guard FileManager.default.fileExists(atPath: iconPath) else {
            throw MCPError.invalidParams("Icon file not found: \(iconPath)")
        }

        // Build ictool arguments:
        // ictool <input> --export-image --output-file <path> --platform <p> --rendition <r> --width <w> --height <h> --scale <s>
        var args = [
            iconPath,
            "--export-image",
            "--output-file", outputPath,
            "--platform", platform,
            "--rendition", rendition,
            "--width", "\(width)",
            "--height", "\(height)",
            "--scale", "\(scale)",
        ]

        // Optional tint/lighting parameters
        if let lightAngle = arguments.getDouble("light_angle") {
            args += ["--light-angle", "\(lightAngle)"]
        }
        if let tintColor = arguments.getDouble("tint_color") {
            args += ["--tint-color", "\(tintColor)"]
        }
        if let tintStrength = arguments.getDouble("tint_strength") {
            args += ["--tint-strength", "\(tintStrength)"]
        }

        let result = try await ProcessResult.run(
            ictoolPath,
            arguments: args,
            mergeStderr: false,
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "ictool export failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        // Verify output was created
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw MCPError.internalError(
                "ictool completed but output file was not created at \(outputPath)",
            )
        }

        return CallTool.Result(
            content: [
                .text(text:
                    "Exported icon to \(outputPath) (\(width)x\(height)@\(scale)x, \(platform), \(rendition))",
                    annotations: nil, _meta: nil),
            ],
        )
    }
}
