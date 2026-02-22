import Foundation

/// Parses macOS `.ips` crash report files from `~/Library/Logs/DiagnosticReports/`.
///
/// The `.ips` format consists of a JSON header line followed by a JSON body containing
/// exception info, termination reasons, thread backtraces, and loaded images.
public enum CrashReportParser: Sendable {
  /// A summary of a parsed crash report.
  public struct CrashSummary: Sendable {
    public let processName: String?
    public let bundleID: String?
    public let captureTime: String?
    public let exceptionType: String?
    public let signal: String?
    public let terminationNamespace: String?
    public let terminationIndicator: String?
    public let terminationReasons: [String]
    public let terminationDetails: [String]
    public let isFatalDyldError: Bool

    /// Formats the summary as a human-readable string.
    public func formatted() -> String {
      var parts: [String] = []

      if let processName {
        parts.append("Process: \(processName)")
      }
      if let bundleID {
        parts.append("Bundle ID: \(bundleID)")
      }
      if let captureTime {
        parts.append("Time: \(captureTime)")
      }

      // Exception
      var exParts: [String] = []
      if let exceptionType { exParts.append(exceptionType) }
      if let signal { exParts.append("(\(signal))") }
      if !exParts.isEmpty {
        parts.append("Exception: \(exParts.joined(separator: " "))")
      }

      // Termination — the most actionable part
      if let terminationIndicator {
        let ns = terminationNamespace ?? ""
        parts.append("Termination: \(ns) — \(terminationIndicator)")
      }
      for reason in terminationReasons {
        parts.append("  \(reason)")
      }
      for detail in terminationDetails {
        parts.append("  \(detail)")
      }

      if isFatalDyldError,
        !parts.contains(where: { $0.contains("DYLD") || $0.contains("Symbol") })
      {
        parts.append("Fatal dyld error (missing symbol or library)")
      }

      return parts.joined(separator: "\n")
    }
  }

  /// The directory where macOS stores crash reports.
  public static let diagnosticReportsDir: String = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/DiagnosticReports").path

  /// Parses an `.ips` crash report file at the given path.
  ///
  /// - Parameter path: Absolute path to the `.ips` file.
  /// - Returns: A ``CrashSummary`` if parsing succeeds, `nil` otherwise.
  public static func parse(at path: String) -> CrashSummary? {
    guard let data = FileManager.default.contents(atPath: path),
      let content = String(data: data, encoding: .utf8)
    else {
      return nil
    }

    // .ips files: JSON header on line 1, then the crash body as JSON
    guard let firstNewline = content.firstIndex(of: "\n") else {
      return nil
    }

    let bodyString = String(content[content.index(after: firstNewline)...])
    guard let bodyData = bodyString.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    else {
      return nil
    }

    return parseJSON(json)
  }

  /// Parses a crash report from its JSON body dictionary.
  ///
  /// Exposed for testing without needing a file on disk.
  public static func parseJSON(_ json: [String: Any]) -> CrashSummary {
    let exception = json["exception"] as? [String: Any]
    let termination = json["termination"] as? [String: Any]
    let bundleInfo = json["bundleInfo"] as? [String: Any]

    return CrashSummary(
      processName: json["procName"] as? String,
      bundleID: bundleInfo?["CFBundleIdentifier"] as? String,
      captureTime: json["captureTime"] as? String,
      exceptionType: exception?["type"] as? String,
      signal: exception?["signal"] as? String,
      terminationNamespace: termination?["namespace"] as? String,
      terminationIndicator: termination?["indicator"] as? String,
      terminationReasons: termination?["reasons"] as? [String] ?? [],
      terminationDetails: termination?["details"] as? [String] ?? [],
      isFatalDyldError: (json["fatalDyldError"] as? Int) != nil
        && (json["fatalDyldError"] as? Int) != 0,
    )
  }

  /// Searches `~/Library/Logs/DiagnosticReports/` for recent `.ips` crash reports.
  ///
  /// - Parameters:
  ///   - processName: Optional process name to filter by (matched against filename and
  ///     `procName` in the JSON header).
  ///   - bundleID: Optional bundle ID to filter by (matched against the JSON header line).
  ///   - minutes: Only include reports from the last N minutes. Defaults to 5.
  /// - Returns: An array of `(path, summary)` tuples, most recent first.
  public static func search(
    processName: String? = nil,
    bundleID: String? = nil,
    minutes: Int = 5,
  ) -> [(path: String, summary: CrashSummary)] {
    let fm = FileManager.default
    let reportsDir = diagnosticReportsDir

    guard let entries = try? fm.contentsOfDirectory(atPath: reportsDir) else {
      return []
    }

    let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
    var results: [(path: String, summary: CrashSummary, modified: Date)] = []

    for entry in entries where entry.hasSuffix(".ips") {
      let fullPath = "\(reportsDir)/\(entry)"

      // Filter by recency
      guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
        let modified = attrs[.modificationDate] as? Date,
        modified > cutoff
      else {
        continue
      }

      // Quick filename pre-filter before parsing the full file
      if let processName,
        !entry.localizedCaseInsensitiveContains(processName)
      {
        // Filename doesn't match — still parse to check procName field,
        // but only if no bundle ID filter either
        if bundleID == nil {
          continue
        }
      }

      guard let summary = parse(at: fullPath) else {
        continue
      }

      // Filter by process name (from parsed JSON)
      if let processName,
        let proc = summary.processName,
        !proc.localizedCaseInsensitiveContains(processName)
      {
        // Filename didn't match and procName didn't match
        if !entry.localizedCaseInsensitiveContains(processName) {
          continue
        }
      }

      // Filter by bundle ID
      if let bundleID,
        let bid = summary.bundleID,
        bid != bundleID
      {
        continue
      }

      results.append((fullPath, summary, modified))
    }

    // Sort most recent first
    results.sort { $0.modified > $1.modified }
    return results.map { ($0.path, $0.summary) }
  }
}
