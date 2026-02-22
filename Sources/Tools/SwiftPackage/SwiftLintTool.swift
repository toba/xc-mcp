import Foundation
import MCP
import XCMCPCore

public struct SwiftLintTool: Sendable {
  private let sessionManager: SessionManager

  public init(sessionManager: SessionManager) {
    self.sessionManager = sessionManager
  }

  public func tool() -> Tool {
    Tool(
      name: "swift_lint",
      description:
        "Run swiftlint on a Swift package or specific paths. Returns violations grouped by file.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "paths": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(
              "Specific file or directory paths to lint. If not specified, lints the package root.",
            ),
          ]),
          "package_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to the Swift package directory. Uses session default if not specified.",
            ),
          ]),
          "fix": .object([
            "type": .string("boolean"),
            "description": .string(
              "Automatically fix violations where possible. Defaults to false.",
            ),
          ]),
        ]),
        "required": .array([]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
    let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
    let paths = arguments.getStringArray("paths")
    let fix = arguments.getBool("fix")

    let executablePath = try await locateBinary("swiftlint")

    var args: [String] = ["lint", "--reporter", "json"]
    if fix {
      args.append("--fix")
    }

    // Add config if present
    let configPath = URL(fileURLWithPath: packagePath)
      .appendingPathComponent(".swiftlint.yml").path
    if FileManager.default.fileExists(atPath: configPath) {
      args.append("--config")
      args.append(configPath)
    }

    if paths.isEmpty {
      args.append(packagePath)
    } else {
      args.append(contentsOf: paths)
    }

    do {
      let result = try await ProcessResult.run(
        executablePath, arguments: args, mergeStderr: false,
      )

      let violations = Self.parseJSONOutput(result.stdout)

      if violations.isEmpty {
        return CallTool.Result(content: [.text("No violations found. Code is clean!")])
      }

      let message = Self.formatViolations(violations)
      return CallTool.Result(content: [.text(message)])
    } catch {
      throw error.asMCPError()
    }
  }

  /// A single swiftlint violation parsed from JSON output.
  struct Violation: Sendable {
    let file: String
    let line: Int
    let column: Int
    let severity: String
    let ruleID: String
    let reason: String
  }

  /// Parses swiftlint JSON reporter output into structured violations.
  static func parseJSONOutput(_ output: String) -> [Violation] {
    guard let data = output.data(using: .utf8),
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return []
    }

    return array.compactMap { dict -> Violation? in
      guard let file = dict["file"] as? String,
        let line = dict["line"] as? Int,
        let severity = dict["severity"] as? String,
        let ruleID = dict["rule_id"] as? String,
        let reason = dict["reason"] as? String
      else {
        return nil
      }
      let column = dict["character"] as? Int ?? 0
      return Violation(
        file: file, line: line, column: column,
        severity: severity, ruleID: ruleID, reason: reason,
      )
    }
  }

  /// Formats violations grouped by file for display.
  static func formatViolations(_ violations: [Violation]) -> String {
    let grouped = Dictionary(grouping: violations) { $0.file }
    let sortedFiles = grouped.keys.sorted()

    var lines = ["\(violations.count) violation(s) found:\n"]

    for file in sortedFiles {
      guard let fileViolations = grouped[file] else { continue }
      lines.append(file)
      for v in fileViolations {
        lines.append("  \(v.line):\(v.column) \(v.severity): \(v.reason) (\(v.ruleID))")
      }
    }

    return lines.joined(separator: "\n")
  }

  private func locateBinary(_ name: String) async throws -> String {
    let homebrewPath = "/opt/homebrew/bin/\(name)"
    if FileManager.default.fileExists(atPath: homebrewPath) {
      return homebrewPath
    }
    let result = try await ProcessResult.run(
      "/usr/bin/which", arguments: [name], mergeStderr: false,
    )
    let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard result.succeeded, !path.isEmpty else {
      throw MCPError.internalError(
        "\(name) not found. Install it with: brew install \(name)",
      )
    }
    return path
  }
}
