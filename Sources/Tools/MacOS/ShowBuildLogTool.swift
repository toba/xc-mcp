import MCP
import XCMCPCore
import Foundation

/// Reads the most recent Xcode build log (`.xcactivitylog`) from DerivedData
/// and extracts errors and warnings.
///
/// When a build hangs or is killed before errors appear in `xcodebuild` output,
/// this tool can retrieve errors from a previous Xcode build attempt stored in
/// the build log. The log is found automatically from DerivedData.
public struct ShowBuildLogTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "show_build_log",
            description:
            "Read errors and warnings from the most recent Xcode build log in DerivedData. "
                + "Use this when a build hangs or times out before errors appear — "
                + "a previous Xcode build may have captured the errors you need.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to show build log for. Uses session default if not specified.",
                        ),
                    ]),
                    "errors_only": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, only show errors (suppress warnings). Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let errorsOnly = arguments.getBool("errors_only")

        // Step 1: Get BUILD_DIR from xcodebuild -showBuildSettings to find DerivedData
        let derivedDataPath = try await findDerivedDataPath(
            projectPath: projectPath, workspacePath: workspacePath, scheme: scheme,
        )

        // Step 2: Find the most recent non-empty .xcactivitylog
        let logsDir = URL(fileURLWithPath: derivedDataPath).appendingPathComponent("Logs/Build")
            .path
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else {
            throw MCPError.internalError("No build logs found at \(logsDir)")
        }

        let logs = entries.filter { $0.hasSuffix(".xcactivitylog") }
            .compactMap { name -> (path: String, date: Date, size: UInt64)? in
                let path = URL(fileURLWithPath: logsDir).appendingPathComponent(name).path
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let date = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? UInt64, size > 0
                else { return nil }
                return (path, date, size)
            }
            .sorted { $0.date > $1.date }

        guard let mostRecent = logs.first else {
            throw MCPError.internalError("No non-empty build logs found in \(logsDir)")
        }

        // Step 3: Decompress and extract errors/warnings
        let decompressed = try await decompressLog(at: mostRecent.path)

        let errorPattern = #/(/[^\s:]+:\d+:\d+: error: [^\n]+)/#
        let warningPattern = #/(/[^\s:]+:\d+:\d+: warning: [^\n]+)/#

        var seenErrors = Set<String>()
        var errors: [String] = []
        var seenWarnings = Set<String>()
        var warnings: [String] = []

        for line in decompressed.split(separator: "\n") {
            let str = String(line)
            if str.contains("error:"), let match = str.firstMatch(of: errorPattern) {
                let error = String(match.1)
                if seenErrors.insert(error).inserted {
                    errors.append(error)
                }
            }
            if !errorsOnly, str.contains("warning:"),
               let match = str.firstMatch(of: warningPattern)
            {
                let warning = String(match.1)
                if seenWarnings.insert(warning).inserted {
                    warnings.append(warning)
                }
            }
        }

        // Step 4: Format output
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let logDate = dateFormatter.string(from: mostRecent.date)

        var text = "## Build Log (\(logDate))\n\n"

        if errors.isEmpty, warnings.isEmpty {
            text += "No errors or warnings found in the most recent build log."
        } else {
            if !errors.isEmpty {
                text += "**\(errors.count) error\(errors.count == 1 ? "" : "s"):**\n\n"
                for error in errors.prefix(50) {
                    text += "  \(error)\n"
                }
                if errors.count > 50 {
                    text += "  (+\(errors.count - 50) more errors)\n"
                }
            }

            if !warnings.isEmpty {
                if !errors.isEmpty { text += "\n" }
                text += "**\(warnings.count) warning\(warnings.count == 1 ? "" : "s"):**\n\n"
                for warning in warnings.prefix(30) {
                    text += "  \(warning)\n"
                }
                if warnings.count > 30 {
                    text += "  (+\(warnings.count - 30) more warnings)\n"
                }
            }
        }

        return CallTool.Result(content: [.text(text)])
    }

    // MARK: - Private

    private func findDerivedDataPath(
        projectPath: String?, workspacePath: String?, scheme: String,
    ) async throws -> String {
        var args: [String] = []
        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }
        args += ["-scheme", scheme, "-showBuildSettings"]

        let result = try await xcodebuildRunner.run(
            arguments: args, timeout: 30, outputTimeout: .seconds(15), onProgress: nil,
        )

        // Extract BUILD_DIR, then go up to the DerivedData project root
        // BUILD_DIR = /Users/.../DerivedData/Project-hash/Build/Products
        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("BUILD_DIR = ") {
                let buildDir = String(trimmed.dropFirst("BUILD_DIR = ".count))
                // Go up from Build/Products to the DerivedData project root
                let url = URL(fileURLWithPath: buildDir)
                    .deletingLastPathComponent() // Products
                    .deletingLastPathComponent() // Build
                return url.path
            }
        }

        throw MCPError.internalError(
            "Could not determine DerivedData path from build settings",
        )
    }

    private func decompressLog(at path: String) async throws -> String {
        let result = try await ProcessResult.run(
            "/usr/bin/gunzip", arguments: ["-c", path], timeout: .seconds(30),
        )
        return result.stdout
    }
}
