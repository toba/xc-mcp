import Foundation
import MCP
import XCMCPCore

public struct XCStringsBatchStatsCoverageTool: Sendable {
  private let pathUtility: PathUtility

  public init(pathUtility: PathUtility) {
    self.pathUtility = pathUtility
  }

  public func tool() -> Tool {
    Tool(
      name: "xcstrings_batch_stats_coverage",
      description:
        "Get token-efficient coverage statistics for multiple xcstrings files at once. Returns compact summary with coverage percentages per language for each file and aggregated totals. Use compact mode to only show languages under 100%.",
      inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
          "files": .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string("Array of paths to xcstrings files"),
          ]),
          "compact": .object([
            "type": .string("boolean"),
            "description": .string(
              "If true, only show languages under 100% coverage (default: true)",
            ),
          ]),
        ]),
        "required": .array([.string("files")]),
      ]),
    )
  }

  public func execute(arguments: [String: Value]) throws -> CallTool.Result {
    let files = arguments.getStringArray("files")
    if files.isEmpty {
      throw MCPError.invalidParams("files array is required and cannot be empty")
    }
    let compact = arguments.getBool("compact", default: true)

    do {
      // Resolve all paths
      let resolvedPaths = try files.map { try pathUtility.resolvePath(from: $0) }

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

      let json: String
      if compact {
        let coverage = try XCStringsParser.getCompactBatchCoverage(paths: resolvedPaths)
        let data = try encoder.encode(coverage)
        json = String(data: data, encoding: .utf8) ?? "{}"
      } else {
        let coverage = try XCStringsParser.getBatchCoverage(paths: resolvedPaths)
        let data = try encoder.encode(coverage)
        json = String(data: data, encoding: .utf8) ?? "{}"
      }

      return CallTool.Result(content: [.text(json)])
    } catch let error as XCStringsError {
      throw error.toMCPError()
    } catch let error as PathError {
      throw MCPError.invalidParams(error.localizedDescription)
    }
  }
}
