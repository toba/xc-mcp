import Foundation

public enum TestPlanFile {
  /// Reads a `.xctestplan` JSON file and returns the top-level dictionary.
  public static func read(from path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw TestPlanFileError.invalidFormat(path)
    }
    return json
  }

  /// Writes a `.xctestplan` JSON dictionary to disk with pretty-printing and sorted keys.
  public static func write(_ json: [String: Any], to path: String) throws {
    let data = try JSONSerialization.data(
      withJSONObject: json,
      options: [.prettyPrinted, .sortedKeys],
    )
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Extracts test target names from a test plan JSON dictionary.
  public static func targetNames(from json: [String: Any]) -> [String] {
    targetEntries(from: json).map(\.name)
  }

  /// Extracts test target entries with name and enabled status from a test plan JSON dictionary.
  ///
  /// Targets without an explicit `"enabled"` key are treated as enabled (Xcode's default).
  public static func targetEntries(from json: [String: Any]) -> [(name: String, enabled: Bool)] {
    guard let testTargets = json["testTargets"] as? [[String: Any]] else {
      return []
    }
    return testTargets.compactMap { entry in
      guard let target = entry["target"] as? [String: Any],
        let name = target["name"] as? String
      else {
        return nil
      }
      let enabled = entry["enabled"] as? Bool ?? true
      return (name: name, enabled: enabled)
    }
  }

  /// Builds a `container:` path for a project URL, used in test plan target entries.
  ///
  /// Returns `"container:<project-filename>"`, e.g. `"container:MyApp.xcodeproj"`.
  public static func containerPath(for projectURL: URL) -> String {
    "container:\(projectURL.lastPathComponent)"
  }

  /// Recursively finds `.xctestplan` files under the given root directory.
  ///
  /// Returns tuples of `(path, json)` for each valid test plan file found.
  public static func findFiles(
    under root: String, maxDepth: Int = 5,
  ) -> [(path: String, json: [String: Any])] {
    let fm = FileManager.default
    var results: [(path: String, json: [String: Any])] = []

    guard
      let enumerator = fm.enumerator(
        at: URL(fileURLWithPath: root),
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles],
      )
    else {
      return results
    }

    let rootURL = URL(fileURLWithPath: root).standardized
    for case let fileURL as URL in enumerator {
      // Enforce max depth
      let relative = fileURL.standardized.path.dropFirst(rootURL.path.count)
      let depth = relative.components(separatedBy: "/").count - 1
      if depth > maxDepth {
        enumerator.skipDescendants()
        continue
      }

      if fileURL.pathExtension == "xctestplan" {
        if let json = try? read(from: fileURL.path) {
          results.append((path: fileURL.path, json: json))
        }
      }
    }

    return results
  }

  public enum TestPlanFileError: Error, CustomStringConvertible {
    case invalidFormat(String)

    public var description: String {
      switch self {
      case .invalidFormat(let path):
        return "File at '\(path)' is not a valid test plan JSON"
      }
    }
  }
}
