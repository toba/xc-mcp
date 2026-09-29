import MCP
import XCMCPCore
import Foundation

/// Reads the most recent Xcode build log (`.xcactivitylog`) from DerivedData and extracts errors
/// and warnings.
///
/// When a build hangs or is killed before errors appear in `xcodebuild` output, this tool can
/// retrieve errors from a previous Xcode build attempt stored in the build log. The log is found
/// automatically from DerivedData.
public struct ShowBuildLogTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = .init(),
        sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "show_build_log",
            description:
                "Read errors and warnings from the most recent Xcode build log in DerivedData. "
                + "Use this when a build hangs or times out before errors appear — "
                + "a previous Xcode build may have captured the errors you need. "
                + "When the newest log is empty (a build that died, such as on a compiler crash), "
                + "it reads the .dia files and the swift-frontend crash report instead.",
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
                ].merging([String: Value].errorsOnlySchemaProperty()) { _, new in new }),
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

        // Step 2: Find the most recent non-empty .xcactivitylog. A newer empty log means the last
        // build died before Xcode wrote it, so the non-empty one belongs to an earlier build. Read
        // the .dia files and crash reports instead. (dcd0c744)
        let newest = BuildLogLocator.logs(inProjectRoot: derivedDataPath, limit: 1).first
        let empty = BuildLogLocator.newestEmptyLog(inProjectRoot: derivedDataPath)

        guard let mostRecent = newest, empty.map({ $0.date <= mostRecent.date }) ?? true else {
            return CallTool.Result.text(EmptyBuildLogFallback.report(
                derivedDataPath: derivedDataPath,
                emptyLog: empty,
                staleLog: newest,
                errorsOnly: errorsOnly,
            ))
        }

        // Step 3: Decompress and extract errors/warnings
        let decompressed = try await BuildLogLocator.decompress(mostRecent)

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
                if seenErrors.insert(error).inserted { errors.append(error) }
            }
            if !errorsOnly,
               str.contains("warning:"),
               let match = str.firstMatch(of: warningPattern)
            {
                let warning = String(match.1)
                if seenWarnings.insert(warning).inserted { warnings.append(warning) }
            }
        }

        // Step 4: Format output
        let logDate = mostRecent.formattedDate

        var text = "## Build Log (\(logDate))\n\n"

        if errors.isEmpty, warnings.isEmpty {
            text += "No errors or warnings found in the most recent build log."
        } else {
            text += BuildLogDiagnosticList.format(errors: errors, warnings: warnings)
        }

        return CallTool.Result.text(text)
    }

    // MARK: - Private

    private func findDerivedDataPath(
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
    ) async throws -> String {
        // Resolve BUILD_DIR through the runner so the same platform-scoped `-derivedDataPath` the
        // macOS build used is applied — otherwise this reads Xcode's default DerivedData location
        // (or the wrong platform slice) and finds no logs.
        try await DerivedDataLocator.findProjectRoot(
            xcodebuildRunner: xcodebuildRunner,
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
        )
    }
}
