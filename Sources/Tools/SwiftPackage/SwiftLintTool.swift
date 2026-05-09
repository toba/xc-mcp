import MCP
import XCMCPCore
import Foundation

public struct SwiftLintTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) { self.sessionManager = sessionManager }

    public func tool() -> Tool {
        .init(
            name: "swift_lint",
            description:
                "Run sm (swiftiomatic) lint on a Swift package or specific paths. Returns violations grouped by file.",
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
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let paths = arguments.getStringArray("paths")

        let executablePath = try await BinaryLocator.find("sm")

        var args: [String] = ["lint", "--reporter", "json", "--parallel", "--recursive"]

        if paths.isEmpty { args.append(packagePath) } else { args.append(contentsOf: paths) }

        do {
            let result = try await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
            )

            let violations = Self.parseJSONOutput(result.stdout)

            if violations.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "No violations found. Code is clean!",
                        annotations: nil,
                        _meta: nil,
                    )
                ])
            }

            let message = Self.formatViolations(violations)
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    /// A single sm lint violation parsed from JSON output.
    struct Violation {
        let file: String
        let line: Int
        let column: Int
        let severity: String
        let rule: String
        let message: String
    }

    /// Parses sm lint JSON reporter output into structured violations.
    static func parseJSONOutput(_ output: String) -> [Violation] {
        let data = Data(output.utf8)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict -> Violation? in
            guard let file = dict["file"] as? String,
                  let line = dict["line"] as? Int,
                  let severity = dict["severity"] as? String,
                  let rule = dict["rule"] as? String,
                  let message = dict["message"] as? String
            else { return nil }
            let column = dict["column"] as? Int ?? 0
            return Violation(
                file: file, line: line, column: column,
                severity: severity, rule: rule, message: message,
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
                lines.append("  \(v.line):\(v.column) \(v.severity): \(v.message) (\(v.rule))")
            }
        }

        return lines.joined(separator: "\n")
    }
}
