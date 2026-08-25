import MCP
import Foundation

/// Extracts build settings from xcodebuild output (JSON or text format).
public enum BuildSettingExtractor {
    /// Checks whether a scheme supports macOS by inspecting `SUPPORTED_PLATFORMS` .
    ///
    /// Queries build settings for the scheme and checks if `macosx` is among the supported
    /// platforms. Throws an `MCPError` with actionable guidance if the project only targets iOS or
    /// other non-macOS platforms.
    ///
    /// - Parameters:
    ///   - runner: The xcodebuild runner to query build settings.
    ///   - projectPath: Path to the .xcodeproj file.
    ///   - workspacePath: Path to the .xcworkspace file.
    ///   - scheme: The scheme to check.
    ///   - configuration: Build configuration (Debug or Release), or `nil` to honor the scheme's
    ///     own configuration.
    ///   - outputTimeout: Silence budget for the query. It matches the budget the caller uses for
    ///     the build that follows, so an unresolved package graph does not abort this pre-pass at a
    ///     shorter limit than the build itself. `nil` disables the check.
    public static func validateMacOSSupport(
        runner: XcodebuildRunner,
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        configuration: String?,
        outputTimeout: Duration? = XcodebuildRunner.outputTimeout,
    ) async throws {
        let settings = try await runner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
            outputTimeout: outputTimeout,
        )

        guard let platforms = extractSetting("SUPPORTED_PLATFORMS", from: settings.stdout) else {
            return
        }

        let platformList = platforms.split(separator: " ").map(String.init)

        if !platformList.contains("macosx") {
            let platformDesc = platformList.joined(separator: ", ")
            throw MCPError.invalidRequest(
                "Scheme '\(scheme)' does not support macOS (supported platforms: \(platformDesc)). "
                    + "Use the xc-simulator server's build/test tools for iOS projects, "
                    + "or add Mac Catalyst support in the Xcode project.",
            )
        }
    }

    /// Decodes the `-json` build-settings array, or nil if the output is text format.
    public static func decodeEntries(_ buildSettings: String) -> [BuildSettingsEntry]? {
        try? JSONDecoder().decode([BuildSettingsEntry].self, from: Data(buildSettings.utf8))
    }

    /// Merges every target entry into one lookup map, first entry winning.
    ///
    /// Empty when the payload is text format rather than `-json`.
    static func mergedSettings(_ buildSettings: String) -> [String: String] {
        guard let entries = decodeEntries(buildSettings) else { return [:] }
        var merged: [String: String] = [:]
        // The per-key scan this replaces returned the first entry that carried the key.
        for entry in entries { merged.merge(entry.buildSettings) { current, _ in current } }
        return merged
    }

    /// Reads every setting in an `xcodebuild -showBuildSettings` payload into one map.
    ///
    /// Decodes the `-json` form first and falls back to the `KEY = value` text form, which is what
    /// the plain `-showBuildSettings` output looks like. A target entry that repeats a key the
    /// first entry already carried does not replace it.
    ///
    /// - Parameter output: The raw output from `xcodebuild -showBuildSettings`.
    /// - Returns: Every setting the payload carries, empty when it carries none.
    public static func parseSettings(from output: String) -> [String: String] {
        let merged = mergedSettings(output)
        if !merged.isEmpty { return merged }

        var settings: [String: String] = [:]

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let equalsRange = trimmed.range(of: " = ") else { continue }
            let key = String(trimmed[trimmed.startIndex..<equalsRange.lowerBound])
            if !key.isEmpty { settings[key] = String(trimmed[equalsRange.upperBound...]) }
        }
        return settings
    }

    /// Extracts a raw build setting value by key from xcodebuild output.
    ///
    /// Tries JSON format first ( `-showBuildSettings -json` ), then falls back to text format (
    /// `KEY = value` ).
    ///
    /// - Parameters:
    ///   - key: The build setting key (e.g. "PRODUCT_BUNDLE_IDENTIFIER").
    ///   - buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The setting value, or nil if not found.
    public static func extractSetting(_ key: String, from buildSettings: String) -> String? {
        BuildSettingSet(buildSettings).value(key)
    }

    /// Extracts the product bundle identifier, skipping unresolved variables.
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The resolved bundle ID, or nil if not found or still contains variables.
    public static func extractBundleID(from buildSettings: String) -> String? {
        BuildSettingSet(buildSettings).bundleID
    }

    /// Extracts the product name, skipping unresolved variables.
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The product name, or nil if not found.
    public static func extractProductName(from buildSettings: String) -> String? {
        BuildSettingSet(buildSettings).productName
    }

    /// Extracts the built app path from build settings.
    ///
    /// Tries `CODESIGNING_FOLDER_PATH` first, then falls back to `TARGET_BUILD_DIR` +
    /// `FULL_PRODUCT_NAME` .
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The app path, or nil if not found.
    public static func extractAppPath(from buildSettings: String) -> String? {
        BuildSettingSet(buildSettings).appPath
    }
}

/// One target's entry in `xcodebuild -showBuildSettings -json` output
///
/// The `-json` form emits every setting value as a string, so a `[String: String]` map carries the
/// whole `buildSettings` object without any per-field casting.
public struct BuildSettingsEntry: Codable, Sendable {
    /// The target the settings belong to. A payload for an aggregate action omits it.
    public let target: String?
    public let buildSettings: [String: String]

    public init(target: String?, buildSettings: [String: String]) {
        self.target = target
        self.buildSettings = buildSettings
    }
}

/// One decoded `xcodebuild -showBuildSettings` payload
///
/// Decoding is the whole cost of a lookup, and a `-json` payload for a large project runs to
/// megabytes. A tool that reads several keys builds one of these and reads it, instead of handing
/// the raw text to one extractor per key and paying a decode each time.
///
/// Falls back to the `KEY = value` text form when the payload is not `-json`, which is what the
/// plain `-showBuildSettings` output looks like.
public struct BuildSettingSet: Sendable {
    /// Every target's settings merged into one map, empty for a text payload.
    private let settings: [String: String]

    private let raw: String

    public init(_ buildSettings: String) {
        settings = BuildSettingExtractor.mergedSettings(buildSettings)
        raw = buildSettings
    }

    /// The raw value for `key`, from the decoded map or the text fallback.
    public func value(_ key: String) -> String? {
        if let value = settings[key] { return value }

        for line in raw.components(separatedBy: .newlines) where line.contains(key) {
            if let equalsRange = line.range(of: " = ") {
                return String(line[equalsRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// The product bundle identifier, or nil when it is missing or still holds a variable.
    public var bundleID: String? {
        if let bundleID = settings["PRODUCT_BUNDLE_IDENTIFIER"], !bundleID.contains("$(") {
            return bundleID
        }

        // Fallback: parse text or JSON-ish line format
        for line in raw.components(separatedBy: .newlines)
            where line.contains("PRODUCT_BUNDLE_IDENTIFIER")
        {
            if let range = line.range(of: "PRODUCT_BUNDLE_IDENTIFIER") {
                let afterKey = String(line[range.upperBound...])
                let cleaned = afterKey.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: " = ", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty, !cleaned.hasPrefix("$") { return cleaned }
            }
        }

        return nil
    }

    /// The product name, or nil when it is missing or still holds a variable.
    public var productName: String? {
        guard let name = value("PRODUCT_NAME"), !name.contains("$(") else { return nil }
        return name
    }

    /// The built app bundle path.
    ///
    /// Prefers `CODESIGNING_FOLDER_PATH`, which is the complete path, and otherwise assembles
    /// `TARGET_BUILD_DIR` and `FULL_PRODUCT_NAME`.
    public var appPath: String? {
        if let path = settings["CODESIGNING_FOLDER_PATH"], path.hasSuffix(".app") { return path }

        if let dir = settings["TARGET_BUILD_DIR"], let name = settings["FULL_PRODUCT_NAME"] {
            return "\(dir)/\(name)"
        }

        let lines = raw.components(separatedBy: .newlines)

        // Fallback: text format. First try CODESIGNING_FOLDER_PATH which is the complete .app path
        for line in lines where line.contains("CODESIGNING_FOLDER_PATH") {
            if let range = line.range(of: "/") {
                let path = String(line[range.lowerBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if path.hasSuffix(".app") { return path }
            }
        }

        // Fallback: try TARGET_BUILD_DIR + FULL_PRODUCT_NAME
        var targetBuildDir: String?
        var fullProductName: String?

        for line in lines {
            if line.contains("TARGET_BUILD_DIR"), !line.contains("EFFECTIVE") {
                if let equalsRange = line.range(of: " = ") {
                    targetBuildDir = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            if line.contains("FULL_PRODUCT_NAME") {
                if let equalsRange = line.range(of: " = ") {
                    fullProductName = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let dir = targetBuildDir, let name = fullProductName { return "\(dir)/\(name)" }

        return nil
    }
}
