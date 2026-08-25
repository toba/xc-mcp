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
                            "Specific file or directory paths to format. A relative path resolves against package_path. A path outside package_path is rejected. If not specified, formats the package root.",
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

        do {
            // sm format takes paths alone and has no package root option, so it resolves a relative
            // path against the server working directory. That directory is unrelated to
            // package_path, and this formatter writes in place, so an unresolved path rewrites
            // another repository.
            if paths.isEmpty {
                args.append(packagePath)
            } else {
                try args.append(
                    contentsOf: PathUtility(basePath: packagePath).resolvePaths(from: paths))
            }

            let result = try await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
            )

            // sm format exits 0 for a run that changed files and for a run that changed none. A
            // nonzero exit means sm never read the paths, so an empty changed list is not proof
            // that the files are formatted.
            guard result.succeeded else {
                throw MCPError.internalError(
                    "sm format failed (exit \(result.exitCode)):\n\(result.errorOutput)",
                )
            }

            let summary = Self.parseJSONOutput(result.stdout)

            if summary.changed.isEmpty {
                return CallTool.Result.text("All files already formatted correctly.")
            }

            var message = "Formatted \(summary.changed.count) file(s):\n"
            message += summary.changed.map(\.file).joined(separator: "\n")

            if !summary.skipped.isEmpty {
                message += "\n\nSkipped \(summary.skipped.count) file(s):\n"
                message += summary.skipped.map { "\($0.file) (\($0.reason))" }.joined(
                    separator: "\n")
            }
            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// A single changed file from the sm format JSON reporter.
    struct ChangedFile: Decodable {
        let file: String
        let bytesBefore: Int
        let bytesAfter: Int

        private enum CodingKeys: String, CodingKey { case file, bytesBefore, bytesAfter }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            // sm omits both byte counts when it reports names alone
            bytesBefore = try container.decodeIfPresent(Int.self, forKey: .bytesBefore) ?? 0
            bytesAfter = try container.decodeIfPresent(Int.self, forKey: .bytesAfter) ?? 0
        }
    }

    /// A skipped file from the sm format JSON reporter.
    struct SkippedFile: Decodable {
        let file: String
        let reason: String

        private enum CodingKeys: String, CodingKey { case file, reason }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            file = try container.decode(String.self, forKey: .file)
            reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        }
    }

    /// Aggregate summary parsed from the sm format JSON reporter.
    struct Summary: Decodable {
        let changed: [ChangedFile]
        let unchanged: [String]
        let skipped: [SkippedFile]

        private enum CodingKeys: String, CodingKey { case changed, unchanged, skipped }

        init() {
            changed = []
            unchanged = []
            skipped = []
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // sm omits a list it has nothing for
            changed = try container.decodeIfPresent([ChangedFile].self, forKey: .changed) ?? []
            unchanged = try container.decodeIfPresent([String].self, forKey: .unchanged) ?? []
            skipped = try container.decodeIfPresent([SkippedFile].self, forKey: .skipped) ?? []
        }
    }

    /// Parses the sm format JSON reporter envelope.
    static func parseJSONOutput(_ output: String) -> Summary {
        let decoder = JSONDecoder()
        // the reporter writes bytes_before and bytes_after
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(Summary.self, from: Data(output.utf8))) ?? Summary()
    }
}
