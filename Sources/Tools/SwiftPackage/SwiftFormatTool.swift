import MCP
import XCMCPCore
import Foundation

public struct SwiftFormatTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) { self.sessionManager = sessionManager }

    public func tool() -> Tool {
        .init(
            name: "swift_format",
            description:
                "Run sm (swiftiomatic) format on a Swift package or specific paths. Returns the list of files that were changed.",
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
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let paths = arguments.getStringArray("paths")

        let executablePath = try await BinaryLocator.find("sm")

        var args: [String] = [
            "format", "--in-place", "--recursive", "--parallel",
            "--reporter", "json",
        ]
        if paths.isEmpty { args.append(packagePath) } else { args.append(contentsOf: paths) }

        do {
            let result = try await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
            )
            let summary = Self.parseJSONOutput(result.stdout)

            if summary.changed.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "All files already formatted correctly.",
                        annotations: nil,
                        _meta: nil,
                    )
                ])
            }

            var message = "Formatted \(summary.changed.count) file(s):\n"
            message += summary.changed.map(\.file).joined(separator: "\n")

            if !summary.skipped.isEmpty {
                message += "\n\nSkipped \(summary.skipped.count) file(s):\n"
                message += summary.skipped.map { "\($0.file) (\($0.reason))" }.joined(
                    separator: "\n")
            }
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    /// A single changed file from the sm format JSON reporter.
    struct ChangedFile {
        let file: String
        let bytesBefore: Int
        let bytesAfter: Int
    }

    /// A skipped file from the sm format JSON reporter.
    struct SkippedFile {
        let file: String
        let reason: String
    }

    /// Aggregate summary parsed from the sm format JSON reporter.
    struct Summary {
        let changed: [ChangedFile]
        let unchanged: [String]
        let skipped: [SkippedFile]
    }

    /// Parses the sm format JSON reporter envelope.
    static func parseJSONOutput(_ output: String) -> Summary {
        let data = Data(output.utf8)
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Summary(changed: [], unchanged: [], skipped: [])
        }

        let changed = (dict["changed"] as? [[String: Any]] ?? []).compactMap { e -> ChangedFile? in
            guard let file = e["file"] as? String else { return nil }
            return ChangedFile(
                file: file,
                bytesBefore: e["bytes_before"] as? Int ?? 0,
                bytesAfter: e["bytes_after"] as? Int ?? 0,
            )
        }
        let unchanged = (dict["unchanged"] as? [String]) ?? []
        let skipped = (dict["skipped"] as? [[String: Any]] ?? []).compactMap { e -> SkippedFile? in
            guard let file = e["file"] as? String else { return nil }
            return SkippedFile(file: file, reason: e["reason"] as? String ?? "")
        }

        return .init(changed: changed, unchanged: unchanged, skipped: skipped)
    }
}
