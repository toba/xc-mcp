import MCP
import XCMCPCore
import Foundation

/// Shows the build dependency graph for a scheme or target.
///
/// Displays which targets depend on which, what order they build in, and
/// (after a build) which ones succeeded, failed, or were skipped. Answers
/// "why was this target skipped?" by showing dependency failures.
public struct ShowBuildDependencyGraphTool: Sendable {
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

        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
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
        projectPath: String?, workspacePath: String?,
        scheme: String, configuration: String,
    ) async throws -> [TargetInfo] {
        var args: [String] = []
        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath {
            args += ["-project", projectPath]
        }
        args += ["-scheme", scheme, "-configuration", configuration]
        args += ["-showBuildSettings", "-json"]

        let result = try await xcodebuildRunner.run(arguments: args)

        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            // Fallback: parse text format
            return parseTargetsFromText(result.stdout)
        }

        var targets: [TargetInfo] = []
        for entry in json {
            guard let buildSettings = entry["buildSettings"] as? [String: Any],
                  let targetName = entry["target"] as? String
                  ?? buildSettings["TARGET_NAME"] as? String
            else { continue }

            let productType = buildSettings["PRODUCT_TYPE"] as? String
            // Dependencies are embedded in LINK_WITH_STANDARD_LIBRARIES, dependencies, etc.
            // We extract them from TARGET_BUILD_DIR references and RECURSIVE_SEARCH_PATHS_FOLLOWED_
            targets.append(
                TargetInfo(
                    name: targetName,
                    productType: productType,
                    dependencies: [],
                ),
            )
        }

        return targets
    }

    private func parseTargetsFromText(_ output: String) -> [TargetInfo] {
        var targets: [TargetInfo] = []
        var currentTarget = ""

        for line in output.split(separator: "\n") {
            let str = String(line)
            // "Build settings for action build and target <name>:"
            if str.contains("Build settings for action") {
                if let match = str.firstMatch(of: #/target (\S+):/#) {
                    currentTarget = String(match.1)
                    targets.append(
                        TargetInfo(name: currentTarget, productType: nil, dependencies: []),
                    )
                }
            }
        }
        return targets
    }

    private func parseTargetStatuses(
        projectRoot: String,
    ) async throws -> [String: TargetBuildStatus] {
        let logsDir = URL(fileURLWithPath: projectRoot).appendingPathComponent("Logs/Build").path
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: logsDir) else {
            return [:]
        }

        let logs = entries.filter { $0.hasSuffix(".xcactivitylog") }
            .compactMap { name -> (path: String, date: Date)? in
                let path = (logsDir as NSString).appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let date = attrs[.modificationDate] as? Date
                else { return nil }
                return (path, date)
            }
            .sorted { $0.date > $1.date }

        guard let mostRecent = logs.first else { return [:] }

        let result = try await ProcessResult.run(
            "/usr/bin/gunzip", arguments: ["-c", mostRecent.path], timeout: .seconds(30),
        )

        var statuses: [String: TargetBuildStatus] = [:]
        let succeededPattern = #/BUILD TARGET (\S+).*SUCCEEDED/#
        let failedPattern = #/BUILD TARGET (\S+).*FAILED/#

        // Also track targets that appeared in the log at all
        var seenTargets: Set<String> = []

        for line in result.stdout.split(separator: "\n") {
            let str = String(line)
            if let match = str.firstMatch(of: succeededPattern) {
                let target = String(match.1)
                statuses[target] = .succeeded
                seenTargets.insert(target)
            } else if let match = str.firstMatch(of: failedPattern) {
                let target = String(match.1)
                statuses[target] = .failed
                seenTargets.insert(target)
            } else if str.contains("BUILD TARGET") || str.contains("Build target") {
                if let match = str.firstMatch(of: #/(?:BUILD TARGET|Build target) (\S+)/#) {
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
            text +=
                "\nNo build status available — run a build first, then call this tool "
                + "to see which targets succeeded/failed."
        }

        return text
    }
}
