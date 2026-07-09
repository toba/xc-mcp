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
    ///   - configuration: Build configuration (Debug or Release), or `nil` to honor the scheme's own
    ///     configuration.
    public static func validateMacOSSupport(
        runner: XcodebuildRunner,
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        configuration: String?,
    ) async throws {
        let settings = try await runner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
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

    /// One target's entry in `xcodebuild -showBuildSettings -json` output.
    ///
    /// The `-json` form emits every setting value as a string, so a `[String: String]` map decodes
    /// the whole `buildSettings` object without any per-field casting.
    private struct SettingsEntry: Decodable {
        let buildSettings: [String: String]
    }

    /// Decodes the `-json` build-settings array, or nil if the output is text format.
    private static func decodeEntries(_ buildSettings: String) -> [SettingsEntry]? {
        try? JSONDecoder().decode([SettingsEntry].self, from: Data(buildSettings.utf8))
    }

    /// Looks up a key in the `-json` build-settings output, scanning every target entry.
    private static func jsonSetting(_ key: String, from buildSettings: String) -> String? {
        guard let entries = decodeEntries(buildSettings) else { return nil }
        for entry in entries { if let value = entry.buildSettings[key] { return value } }
        return nil
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
        // Try JSON format first
        if let value = jsonSetting(key, from: buildSettings) { return value }

        // Fallback: parse text format (key = value)
        let lines = buildSettings.components(separatedBy: .newlines)

        for line in lines where line.contains(key) {
            if let equalsRange = line.range(of: " = ") {
                return String(line[equalsRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Extracts the product bundle identifier, skipping unresolved variables.
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The resolved bundle ID, or nil if not found or still contains variables.
    public static func extractBundleId(from buildSettings: String) -> String? {
        // Try JSON format first (most reliable)
        if let bundleId = jsonSetting("PRODUCT_BUNDLE_IDENTIFIER", from: buildSettings),
           !bundleId.contains("$(") { return bundleId }

        // Fallback: parse text or JSON-ish line format
        let lines = buildSettings.components(separatedBy: .newlines)

        for line in lines where line.contains("PRODUCT_BUNDLE_IDENTIFIER") {
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

    /// Extracts the product name, skipping unresolved variables.
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The product name, or nil if not found.
    public static func extractProductName(from buildSettings: String) -> String? {
        if let value = extractSetting("PRODUCT_NAME", from: buildSettings),
           !value.contains("$(") { return value }
        return nil
    }

    /// Extracts the built app path from build settings.
    ///
    /// Tries `CODESIGNING_FOLDER_PATH` first, then falls back to `TARGET_BUILD_DIR` +
    /// `FULL_PRODUCT_NAME` .
    ///
    /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings` .
    /// - Returns: The app path, or nil if not found.
    public static func extractAppPath(from buildSettings: String) -> String? {
        // Prefer the JSON form: CODESIGNING_FOLDER_PATH is the complete .app path, otherwise
        // assemble TARGET_BUILD_DIR + FULL_PRODUCT_NAME.
        if let path = jsonSetting("CODESIGNING_FOLDER_PATH", from: buildSettings),
           path.hasSuffix(".app") { return path }

        if let dir = jsonSetting("TARGET_BUILD_DIR", from: buildSettings),
           let name = jsonSetting("FULL_PRODUCT_NAME", from: buildSettings) {
            return "\(dir)/\(name)"
        }

        let lines = buildSettings.components(separatedBy: .newlines)

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
