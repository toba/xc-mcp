import Foundation

/// Extracts build settings from xcodebuild output (JSON or text format).
public enum BuildSettingExtractor {
  /// Extracts a raw build setting value by key from xcodebuild output.
  ///
  /// Tries JSON format first (`-showBuildSettings -json`), then falls back
  /// to text format (`KEY = value`).
  ///
  /// - Parameters:
  ///   - key: The build setting key (e.g. "PRODUCT_BUNDLE_IDENTIFIER").
  ///   - buildSettings: The raw output from `xcodebuild -showBuildSettings`.
  /// - Returns: The setting value, or nil if not found.
  public static func extractSetting(_ key: String, from buildSettings: String) -> String? {
    // Try JSON format first
    if let data = buildSettings.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    {
      for entry in json {
        if let settings = entry["buildSettings"] as? [String: Any],
          let value = settings[key] as? String
        {
          return value
        }
      }
    }

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
  /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings`.
  /// - Returns: The resolved bundle ID, or nil if not found or still contains variables.
  public static func extractBundleId(from buildSettings: String) -> String? {
    // Try JSON format first (most reliable)
    if let data = buildSettings.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    {
      for targetSettings in parsed {
        if let settings = targetSettings["buildSettings"] as? [String: Any],
          let bundleId = settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String
        {
          if !bundleId.contains("$(") {
            return bundleId
          }
        }
      }
    }

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
        if !cleaned.isEmpty, !cleaned.hasPrefix("$") {
          return cleaned
        }
      }
    }

    return nil
  }

  /// Extracts the product name, skipping unresolved variables.
  ///
  /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings`.
  /// - Returns: The product name, or nil if not found.
  public static func extractProductName(from buildSettings: String) -> String? {
    if let value = extractSetting("PRODUCT_NAME", from: buildSettings),
      !value.contains("$(")
    {
      return value
    }
    return nil
  }

  /// Extracts the built app path from build settings.
  ///
  /// Tries `CODESIGNING_FOLDER_PATH` first, then falls back to
  /// `TARGET_BUILD_DIR` + `FULL_PRODUCT_NAME`.
  ///
  /// - Parameter buildSettings: The raw output from `xcodebuild -showBuildSettings`.
  /// - Returns: The app path, or nil if not found.
  public static func extractAppPath(from buildSettings: String) -> String? {
    let lines = buildSettings.components(separatedBy: .newlines)

    // First try CODESIGNING_FOLDER_PATH which is the complete .app path
    for line in lines where line.contains("CODESIGNING_FOLDER_PATH") {
      if let range = line.range(of: "/") {
        let path = String(line[range.lowerBound...])
          .trimmingCharacters(in: .whitespaces)
          .replacingOccurrences(of: "\"", with: "")
          .replacingOccurrences(of: ",", with: "")
        if path.hasSuffix(".app") {
          return path
        }
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

    if let dir = targetBuildDir, let name = fullProductName {
      return "\(dir)/\(name)"
    }

    return nil
  }
}
