import MCP
import Foundation

/// Codable representation of an Icon Composer `.icon` bundle's `icon.json` manifest.
///
/// Matches the format produced by Apple's Icon Composer app and consumed by `ictool`. Reference:
/// [ethbak/icon-composer-mcp](https://github.com/ethbak/icon-composer-mcp)
public struct IconManifest: Codable, Sendable {
    public var groups: [Group]
    public var supportedPlatforms: SupportedPlatforms
    public var fill: Fill?
    public var fillSpecializations: [Specialization<Fill>]?

    public init(
        groups: [Group],
        supportedPlatforms: SupportedPlatforms = .default,
        fill: Fill? = nil,
        fillSpecializations: [Specialization<Fill>]? = nil
    ) {
        self.groups = groups
        self.supportedPlatforms = supportedPlatforms
        self.fill = fill
        self.fillSpecializations = fillSpecializations
    }

    enum CodingKeys: String, CodingKey {
        case groups
        case supportedPlatforms = "supported-platforms"
        case fill
        case fillSpecializations = "fill-specializations"
    }

    // MARK: - Fill

    /// Background fill — solid color, linear gradient, or automatic gradient.
    public enum Fill: Codable, Sendable {
        case solid(String)
        case linearGradient([String], orientation: GradientOrientation)
        case automaticGradient(String)

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let color = try container.decodeIfPresent(String.self, forKey: .solid) {
                self = .solid(color)
            } else if let color = try container.decodeIfPresent(
                String.self, forKey: .automaticGradient
            ) {
                self = .automaticGradient(color)
            } else if let colors = try container.decodeIfPresent(
                [String].self, forKey: .linearGradient
            ) {
                let orientation = try container.decode(
                    GradientOrientation.self, forKey: .orientation
                )
                self = .linearGradient(colors, orientation: orientation)
            } else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath, debugDescription: "Unknown fill type"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
                case let .solid(color): try container.encode(color, forKey: .solid)
                case let .automaticGradient(color):
                    try container.encode(color, forKey: .automaticGradient)
                case let .linearGradient(colors, orientation):
                    try container.encode(colors, forKey: .linearGradient)
                    try container.encode(orientation, forKey: .orientation)
            }
        }

        enum CodingKeys: String, CodingKey {
            case solid
            case linearGradient = "linear-gradient"
            case automaticGradient = "automatic-gradient"
            case orientation
        }

        /// Creates a fill from a hex color string (e.g. "#FF8800" or "FF8800").
        public static func fromHex(_ hex: String) -> Fill { .automaticGradient(hexToSRGB(hex)) }
    }

    // MARK: - Gradient Orientation

    public struct GradientOrientation: Codable, Sendable {
        public var start: Point
        public var stop: Point

        public init(start: Point, stop: Point) {
            self.start = start
            self.stop = stop
        }
    }

    public struct Point: Codable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    // MARK: - Specialization

    public struct Specialization<T: Codable & Sendable>: Codable, Sendable {
        public var appearance: String?
        public var idiom: String?
        public var value: T

        public init(appearance: String? = nil, idiom: String? = nil, value: T) {
            self.appearance = appearance
            self.idiom = idiom
            self.value = value
        }
    }

    // MARK: - Group

    public struct Group: Codable, Sendable {
        public var layers: [Layer]
        public var name: String?
        public var hidden: Bool?
        public var blendMode: String?
        public var blurMaterial: Double?
        public var lighting: String?
        public var shadow: Shadow?
        public var specular: Bool?
        public var translucency: Translucency?
        public var opacity: Double?
        public var position: Position?

        public init(
            layers: [Layer],
            name: String? = nil,
            hidden: Bool? = nil,
            blendMode: String? = nil,
            blurMaterial: Double? = nil,
            lighting: String? = nil,
            shadow: Shadow? = nil,
            specular: Bool? = nil,
            translucency: Translucency? = nil,
            opacity: Double? = nil,
            position: Position? = nil
        ) {
            self.layers = layers
            self.name = name
            self.hidden = hidden
            self.blendMode = blendMode
            self.blurMaterial = blurMaterial
            self.lighting = lighting
            self.shadow = shadow
            self.specular = specular
            self.translucency = translucency
            self.opacity = opacity
            self.position = position
        }

        enum CodingKeys: String, CodingKey {
            case layers, name, hidden, lighting, shadow, specular, translucency, opacity, position
            case blendMode = "blend-mode"
            case blurMaterial = "blur-material"
        }
    }

    // MARK: - Layer

    public struct Layer: Codable, Sendable {
        public var imageName: String
        public var name: String
        public var hidden: Bool?
        public var opacity: Double?
        public var blendMode: String?
        public var fill: Fill?
        public var glass: Bool?
        public var position: Position?

        public init(
            imageName: String,
            name: String,
            hidden: Bool? = nil,
            opacity: Double? = nil,
            blendMode: String? = nil,
            fill: Fill? = nil,
            glass: Bool? = nil,
            position: Position? = nil
        ) {
            self.imageName = imageName
            self.name = name
            self.hidden = hidden
            self.opacity = opacity
            self.blendMode = blendMode
            self.fill = fill
            self.glass = glass
            self.position = position
        }

        enum CodingKeys: String, CodingKey {
            case name, hidden, opacity, fill, glass, position
            case imageName = "image-name"
            case blendMode = "blend-mode"
        }
    }

    // MARK: - Shadow

    public struct Shadow: Codable, Sendable {
        public var kind: String
        public var opacity: Double

        public init(kind: String = "neutral", opacity: Double = 0.5) {
            self.kind = kind
            self.opacity = opacity
        }
    }

    // MARK: - Translucency

    public struct Translucency: Codable, Sendable {
        public var enabled: Bool
        public var value: Double

        public init(enabled: Bool = true, value: Double = 0.5) {
            self.enabled = enabled
            self.value = value
        }
    }

    // MARK: - Position

    public struct Position: Codable, Sendable {
        public var scale: Double
        public var translationInPoints: [Double]

        public init(scale: Double = 1.0, translationInPoints: [Double] = [0, 0]) {
            self.scale = scale
            self.translationInPoints = translationInPoints
        }

        /// Merges the optional scale and offset arguments onto a position.
        ///
        /// An argument the caller omits keeps the value `existing` carries. A group or layer with
        /// no position starts from scale 1 at the origin.
        ///
        /// - Parameters:
        ///   - existing: The position already on the group or the layer, or `nil`.
        ///   - scale: The `scale` argument.
        ///   - offsetX: The `offset_x` argument.
        ///   - offsetY: The `offset_y` argument.
        public static func merging(
            _ existing: Position?,
            scale: Double?,
            offsetX: Double?,
            offsetY: Double?,
        ) -> Position {
            .init(
                scale: scale ?? existing?.scale ?? 1.0,
                translationInPoints: [
                    offsetX ?? existing?.translationInPoints.first ?? 0,
                    offsetY ?? existing?.translationInPoints.dropFirst().first ?? 0,
                ],
            )
        }

        /// The position written the way the icon tools report it.
        public var summary: String {
            let x = translationInPoints.first ?? 0
            let y = translationInPoints.dropFirst().first ?? 0
            return "scale=\(scale), offset=[\(x), \(y)]"
        }

        enum CodingKeys: String, CodingKey {
            case scale
            case translationInPoints = "translation-in-points"
        }
    }

    // MARK: - Supported Platforms

    public struct SupportedPlatforms: Codable, Sendable {
        public var squares: SquaresValue?
        public var circles: [String]?

        public init(squares: SquaresValue? = .shared, circles: [String]? = ["watchOS"]) {
            self.squares = squares
            self.circles = circles
        }

        public static let `default` = SupportedPlatforms()

        public enum SquaresValue: Codable, Sendable {
            case shared
            case platforms([String])

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()

                if let str = try? container.decode(String.self), str == "shared" {
                    self = .shared
                } else {
                    self = try .platforms(container.decode([String].self))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()

                switch self {
                    case .shared: try container.encode("shared")
                    case let .platforms(list): try container.encode(list)
                }
            }
        }
    }

    // MARK: - Hex Color Conversion

    /// Converts a color argument to the notation `icon.json` stores.
    ///
    /// A hex string becomes Apple's sRGB notation. Every other value passes through, because the
    /// manifest also names a color from an asset catalog.
    ///
    /// - Parameter color: A hex string with or without a leading `#`, or an asset catalog name.
    public static func resolveColor(_ color: String) -> String {
        color.hasPrefix("#") || (color.count == 6 && color.allSatisfy(\.isHexDigit))
            ? hexToSRGB(color)
            : color
    }

    /// Converts a color argument to a fill, the way every icon tool that takes one does.
    ///
    /// - Parameter color: A hex string with or without a leading `#`, or an asset catalog name.
    public static func resolveFill(_ color: String) -> Fill {
        .automaticGradient(resolveColor(color))
    }

    /// Converts a hex color string to Apple's sRGB notation: `"srgb:R,G,B,1.00000"`.
    public static func hexToSRGB(_ hex: String) -> String {
        var h = hex
        if h.hasPrefix("#") { h = String(h.dropFirst()) }

        guard h.count == 6,
              let r = UInt8(h.prefix(2), radix: 16),
              let g = UInt8(h.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(h.dropFirst(4).prefix(2), radix: 16)
        else {
            return hex  // pass through if unparseable
        }

        let rf = String(format: "%.5f", Double(r) / 255.0)
        let gf = String(format: "%.5f", Double(g) / 255.0)
        let bf = String(format: "%.5f", Double(b) / 255.0)
        return "srgb:\(rf),\(gf),\(bf),1.00000"
    }
}

// MARK: - JSON Encoding

public extension IconManifest {
    /// Reads and decodes `icon.json` from a `.icon` bundle directory.
    static func read(from iconBundlePath: String) throws -> IconManifest {
        let jsonURL = URL(fileURLWithPath: iconBundlePath).appendingPathComponent("icon.json")
        let data = try Data(contentsOf: jsonURL)
        return try JSONDecoder().decode(IconManifest.self, from: data)
    }

    /// Reads the manifest of a `.icon` bundle, rejecting a path that is not on disk.
    ///
    /// Every icon tool checks the bundle before it reads. A missing bundle is a caller mistake, so
    /// it reports as `invalidParams` rather than as a decoding failure.
    ///
    /// - Parameter iconBundlePath: The `.icon` bundle directory.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the bundle is absent, or a decoding error.
    static func open(_ iconBundlePath: String) throws -> IconManifest {
        guard FileManager.default.fileExists(atPath: iconBundlePath) else {
            throw MCPError.invalidParams("Icon bundle not found: \(iconBundlePath)")
        }
        return try read(from: iconBundlePath)
    }

    /// Rejects a group index that names no group.
    ///
    /// - Parameter index: The `group_index` argument.
    /// - Throws: ``MCPError/invalidParams(_:)`` naming the valid range.
    func validateGroupIndex(_ index: Int) throws(MCPError) {
        guard index >= 0, index < groups.count else {
            throw .invalidParams("group_index \(index) out of range (0..<\(groups.count))")
        }
    }

    /// Encodes to pretty-printed, sorted-keys JSON data.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Writes `icon.json` into the given `.icon` bundle directory.
    func write(to iconBundlePath: String) throws {
        let data = try jsonData()
        let jsonURL = URL(fileURLWithPath: iconBundlePath).appendingPathComponent("icon.json")
        try data.write(to: jsonURL)
    }

    /// Lists asset filenames in the bundle's `Assets/` directory.
    static func listAssets(in iconBundlePath: String) -> [String] {
        let assetsDir = URL(fileURLWithPath: iconBundlePath).appendingPathComponent("Assets").path
        return (try? FileManager.default.contentsOfDirectory(atPath: assetsDir)) ?? []
    }

    /// Removes an asset file from the bundle's `Assets/` directory if it exists.
    static func removeAsset(_ filename: String, from iconBundlePath: String) throws {
        let path = URL(fileURLWithPath: iconBundlePath)
            .appendingPathComponent("Assets")
            .appendingPathComponent(filename)
            .path
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    /// Returns all image filenames referenced by layers in the manifest.
    var referencedAssets: Set<String> {
        var names = Set<String>()
        for group in groups { for layer in group.layers { names.insert(layer.imageName) } }
        return names
    }
}
