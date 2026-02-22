import Foundation
import MCP
import XCMCPCore

public struct SwiftFormatTool: Sendable {
  private let sessionManager: SessionManager

  public init(sessionManager: SessionManager) {
    self.sessionManager = sessionManager
  }

  public func tool() -> Tool {
    Tool(
      name: "swift_format",
      description:
        "Run swiftformat on a Swift package or specific paths. Returns the list of files that were formatted.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "paths": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(
              "Specific file or directory paths to format. If not specified, formats the package root.",
            ),
          ]),
          "package_path": .object([
            "type": .string("string"),
            "description": .string(
              "Path to the Swift package directory. Uses session default if not specified.",
            ),
          ]),
          "dry_run": .object([
            "type": .string("boolean"),
            "description": .string(
              "Preview changes without modifying files. Defaults to false.",
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
    let dryRun = arguments.getBool("dry_run")

    let executablePath = try await locateBinary("swiftformat")

    var args: [String] = []
    if paths.isEmpty {
      args.append(packagePath)
    } else {
      args.append(contentsOf: paths)
    }
    args.append("--verbose")

    if dryRun {
      args.append("--dryrun")
    }

    // Add config if present
    let configPath = URL(fileURLWithPath: packagePath)
      .appendingPathComponent(".swiftformat").path
    if FileManager.default.fileExists(atPath: configPath) {
      args.append("--config")
      args.append(configPath)
    }

    do {
      let result = try await ProcessResult.run(executablePath, arguments: args)
      let formatted = Self.parseVerboseOutput(result.output)

      if dryRun {
        if formatted.isEmpty {
          return CallTool.Result(content: [.text("No formatting changes needed.")])
        }
        var message = "\(formatted.count) file(s) would be changed:\n"
        message += formatted.joined(separator: "\n")
        return CallTool.Result(content: [.text(message)])
      }

      if formatted.isEmpty {
        return CallTool.Result(content: [.text("All files already formatted correctly.")])
      }

      var message = "Formatted \(formatted.count) file(s):\n"
      message += formatted.joined(separator: "\n")
      return CallTool.Result(content: [.text(message)])
    } catch {
      throw error.asMCPError()
    }
  }

  /// Parses swiftformat verbose output to extract files that were changed.
  ///
  /// Verbose output lines for changed files look like:
  /// `*./Sources/Foo.swift`
  /// Lines for unchanged files look like:
  /// `./Sources/Bar.swift`
  static func parseVerboseOutput(_ output: String) -> [String] {
    output.split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line -> String? in
        guard line.hasPrefix("*") else { return nil }
        return String(line.dropFirst())
      }
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
