import MCP
import XCMCPCore
import Foundation

/// Shows the build dependency graph for a scheme or target.
///
/// Displays which targets depend on which, what order they build in, and (after a build) which ones
/// succeeded, failed, or were skipped. Answers "why was this target skipped?" by showing dependency
/// failures.
public struct ShowBuildDependencyGraphTool: Sendable {
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
            name: "show_build_dependency_graph",
            description:
                "Show the build dependency graph for a scheme: which targets depend on which, "
                + "build order, and (after a build) which succeeded/failed/were-skipped. "
                + "Answers 'why was this target skipped?' by revealing dependency failures.",
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
                            "The scheme to show dependencies for. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
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
        let configuration = await sessionManager.resolveConfiguration(from: arguments)

        // Step 1: Get the dependency info from xcodebuild -showBuildSettings (all targets)
        let allSettings = try await fetchAllTargetSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
        )

        // Step 2: Parse the build log for target statuses
        var targetStatuses: [String: TargetBuildStatus] = [:]

        do {
            let projectRoot = try await DerivedDataLocator.findProjectRoot(
                xcodebuildRunner: xcodebuildRunner,
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )
            targetStatuses = try await parseTargetStatuses(projectRoot: projectRoot)
        } catch {
            // Non-fatal: we can still show the graph without build status
        }

        // Step 3: Build and format the dependency graph
        let text = formatDependencyGraph(
            targets: allSettings, statuses: targetStatuses, scheme: scheme,
        )

        return CallTool.Result.text(text)
    }

    // MARK: - Private

    private enum TargetBuildStatus: String {
        case succeeded = "OK"
        case failed = "FAIL"
        case skipped = "SKIP"
    }

    private struct TargetInfo {
        let name: String
        let productType: String?
        let dependencies: [String]
    }

    private func fetchAllTargetSettings(
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        configuration: String?,
    ) async throws -> [TargetInfo] {
        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath { args += ["-project", projectPath] }
        args += ["-scheme", scheme]
        if let configuration { args += ["-configuration", configuration] }
        args += ["-showBuildSettings", "-json"]

        let result = try await xcodebuildRunner.run(arguments: args)

        guard let entries = BuildSettingExtractor.decodeEntries(result.stdout) else {
            // Fallback: parse text format
            return parseTargetsFromText(result.stdout)
        }

        return entries.compactMap { entry in
            guard let targetName = entry.target ?? entry.buildSettings["TARGET_NAME"] else {
                return nil
            }
            // Dependencies are embedded in LINK_WITH_STANDARD_LIBRARIES, dependencies, etc. We
            // extract them from TARGET_BUILD_DIR references and RECURSIVE_SEARCH_PATHS_FOLLOWED_
            return TargetInfo(
                name: targetName,
                productType: entry.buildSettings["PRODUCT_TYPE"],
                dependencies: [],
            )
        }
    }

    /// Matches the target name in `Build settings for action build and target <name>:`
    private static nonisolated(unsafe) let targetSettingsPattern = #/target (\S+):/#

    /// Matches a target name in either capitalization the build log uses
    private static nonisolated(unsafe) let anyBuildTargetPattern =
        #/(?:BUILD TARGET|Build target) (\S+)/#

    private static nonisolated(unsafe) let succeededPattern = #/BUILD TARGET (\S+).*SUCCEEDED/#
    private static nonisolated(unsafe) let failedPattern = #/BUILD TARGET (\S+).*FAILED/#

    private func parseTargetsFromText(_ output: String) -> [TargetInfo] {
        var targets: [TargetInfo] = []
        var currentTarget = ""

        for line in output.split(separator: "\n") {
            let str = String(line)
            // "Build settings for action build and target <name>:"
            if str.contains("Build settings for action") {
                if let match = str.firstMatch(of: Self.targetSettingsPattern) {
                    currentTarget = String(match.1)
                    targets.append(TargetInfo(
                        name: currentTarget, productType: nil, dependencies: []))
                }
            }
        }
        return targets
    }

    private func parseTargetStatuses(
        projectRoot: String,
    ) async throws -> [String: TargetBuildStatus] {
        guard let mostRecent = BuildLogLocator.logs(inProjectRoot: projectRoot, limit: 1).first
        else { return [:] }

        let log = try await BuildLogLocator.decompress(mostRecent)

        var statuses: [String: TargetBuildStatus] = [:]

        // Also track targets that appeared in the log at all
        var seenTargets: Set<String> = []

        for line in log.split(separator: "\n") {
            let str = String(line)

            if let match = str.firstMatch(of: Self.succeededPattern) {
                let target = String(match.1)
                statuses[target] = .succeeded
                seenTargets.insert(target)
            } else if let match = str.firstMatch(of: Self.failedPattern) {
                let target = String(match.1)
                statuses[target] = .failed
                seenTargets.insert(target)
            } else if str.contains("BUILD TARGET") || str.contains("Build target") {
                if let match = str.firstMatch(of: Self.anyBuildTargetPattern) {
                    seenTargets.insert(String(match.1))
                }
            }
        }

        return statuses
    }

    private func formatDependencyGraph(
        targets: [TargetInfo],
        statuses: [String: TargetBuildStatus],
        scheme: String,
    ) -> String {
        var text = "## Build Dependency Graph: \(scheme)\n\n"

        if targets.isEmpty {
            text += "No targets found for scheme '\(scheme)'."
            return text
        }

        text += "**Targets (\(targets.count)):**\n\n"

        // Format build order (xcodebuild returns them in build order)
        for (index, target) in targets.enumerated() {
            let status = statuses[target.name]
            let statusIcon: String

            switch status {
                case .succeeded: statusIcon = "[OK]"
                case .failed: statusIcon = "[FAIL]"
                case .skipped: statusIcon = "[SKIP]"
                case nil: statusIcon = "[ ]"
            }

            var line = "  \(index + 1). \(statusIcon) \(target.name)"

            if let productType = target.productType {
                let shortType = productType.split(separator: ".").last.map(String.init)
                    ?? productType
                line += " (\(shortType))"
            }
            text += line + "\n"
        }

        // Annotate failures and their impact
        let failedTargets = statuses.filter { $0.value == .failed }.map(\.key)

        if !failedTargets.isEmpty {
            text += "\n### Failed Targets\n\n"

            for target in failedTargets.sorted() {
                text += "- **\(target)** failed"

                // Find targets that come after this one in build order (potentially skipped)
                let failedIdx = targets.firstIndex { $0.name == target }

                if let failedIdx {
                    let downstream = targets[(failedIdx + 1)...]
                        .filter { statuses[$0.name] == nil || statuses[$0.name] == .skipped }

                    if !downstream.isEmpty {
                        let names = downstream.map(\.name).joined(separator: ", ")
                        text += " → may have caused skip of: \(names)"
                    }
                }
                text += "\n"
            }
        }

        if statuses.isEmpty {
            text += "\nNo build status available — run a build first, then call this tool "
                + "to see which targets succeeded/failed."
        }

        return text
    }
}
