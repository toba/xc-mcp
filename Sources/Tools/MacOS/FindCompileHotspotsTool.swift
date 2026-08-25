import MCP
import XCMCPCore
import Foundation

/// Finds slow-to-type-check Swift functions and expressions by injecting the frontend's
/// `-warn-long-function-bodies` / `-warn-long-expression-type-checking` diagnostics into a build
/// and ranking the emitted warnings.
///
/// Nothing else in the server surfaces per-declaration type-checking cost. The payoff is largest on
/// big Swift codebases where a handful of complex expressions dominate compile time. Read-only:
/// injects compiler flags via a command-line `OTHER_SWIFT_FLAGS` override (preserving inherited
/// flags) and parses the resulting warnings; it does not modify the project.
public struct FindCompileHotspotsTool: Sendable {
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
            name: "find_compile_hotspots",
            description: "Find slow-to-type-check Swift functions and expressions. Injects "
                + "-warn-long-function-bodies and -warn-long-expression-type-checking into a build "
                + "and returns a ranked list of the slowest declarations and the files that cost the "
                + "most type-checking time. Cleans by default so every file recompiles (an "
                + "incremental build emits no warnings for unchanged files). Read-only.",
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
                            "The scheme to build. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration. Defaults to Debug."),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Architecture to build for (arm64 or x86_64). Defaults to the current "
                                + "machine's architecture.",
                        ),
                    ]),
                    "threshold_ms": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Warn when a function body or expression takes longer than this many "
                                + "milliseconds to type-check. Defaults to 100.",
                        ),
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum number of hotspots to list in each ranked section. Defaults to "
                                + "25.",
                        ),
                    ]),
                    "clean": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Clean before building so every file recompiles. Defaults to true. Set "
                                + "false to only re-check files changed since the last build.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for the build. Defaults to 600.",
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
        let configuration = await sessionManager.resolveConfiguration(from: arguments) ?? "Debug"
        let arch = arguments.getString("arch")
        let thresholdMs = max(arguments.getInt("threshold_ms") ?? 100, 1)
        let limit = max(arguments.getInt("limit") ?? 25, 1)
        let clean = arguments.getBool("clean", default: true)
        let timeout = arguments.resolveTimeout(default: 600)

        var destination = XcodebuildRunner.macOSDestination
        if let arch { destination += ",arch=\(arch)" }

        let scopedDerivedData = DerivedDataScoper.effectivePath(
            workspacePath: workspacePath, projectPath: projectPath, destination: destination,
        )

        // Preserve the project's own flags via $(inherited); xcodebuild expands it for command-line
        // build-setting overrides.
        let swiftFlags = "OTHER_SWIFT_FLAGS=$(inherited)"
            + " -Xfrontend -warn-long-function-bodies=\(thresholdMs)"
            + " -Xfrontend -warn-long-expression-type-checking=\(thresholdMs)"

        var args: [String] = []

        if let workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath { args += ["-project", projectPath] }
        if let scopedDerivedData { args += ["-derivedDataPath", scopedDerivedData] }
        args += ["-scheme", scheme, "-destination", destination, "-configuration", configuration]
        args += clean ? ["clean", "build"] : ["build"]
        args += [swiftFlags]

        let result = try await xcodebuildRunner.run(
            arguments: args, timeout: timeout, outputTimeout: nil, onProgress: nil,
        )

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )
        let hotspots = Self.parseHotspots(result.output, projectRoot: projectRoot)
        let text = Self.formatReport(
            hotspots: hotspots, thresholdMs: thresholdMs, limit: limit,
            buildSucceeded: result.succeeded,
        )
        return CallTool.Result.text(text)
    }

    // MARK: - Parsing

    struct Hotspot: Sendable, Equatable {
        let file: String
        let line: Int
        let column: Int
        let kind: Kind
        let description: String
        let milliseconds: Int

        enum Kind: String, Sendable { case functionBody = "function body", expression }
    }

    static func parseHotspots(_ output: String, projectRoot: String? = nil) -> [Hotspot] {
        // Matches frontend timing warnings, e.g.
        // `/path/File.swift:12:5: warning: expression took 152ms to type-check (limit: 100ms)`. The
        // wording between the location and `took Nms` varies (function bodies name the decl), so
        // the middle is captured loosely and classified afterward.
        let warningPattern =
            #/^(.+?\.swift):(\d+):(\d+): warning: (.*?)took (\d+)ms to type-?check/#

        var hotspots: [Hotspot] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let match = String(line).firstMatch(of: warningPattern),
                  let lineNo = Int(match.2),
                  let col = Int(match.3),
                  let ms = Int(match.5) else { continue }

            let middle = String(match.4).lowercased()
            let kind: Hotspot.Kind = middle.contains("expression") ? .expression : .functionBody
            var path = String(match.1)

            if let projectRoot, path.hasPrefix(projectRoot) {
                path = String(path.dropFirst(projectRoot.count)).trimmingCharacters(in:
                        CharacterSet(charactersIn: "/"))
            }
            hotspots.append(Hotspot(
                file: path, line: lineNo, column: col, kind: kind,
                description: String(match.4).trimmingCharacters(in: .whitespaces), milliseconds: ms,
            ))
        }
        // xcodebuild re-emits identical warnings across incremental passes; keep the worst per
        // site.
        var byKey: [String: Hotspot] = [:]

        for spot in hotspots {
            let key = "\(spot.file):\(spot.line):\(spot.column)"
            if let existing = byKey[key], existing.milliseconds >= spot.milliseconds { continue }
            byKey[key] = spot
        }
        return byKey.values.sorted { $0.milliseconds > $1.milliseconds }
    }

    /// Aggregates per-file cost: total type-check time attributed to that file and hotspot count.
    static func fileTotals(_ hotspots: [Hotspot]) -> [(file: String, totalMs: Int, count: Int)] {
        var totals: [String: (ms: Int, count: Int)] = [:]

        for spot in hotspots {
            var entry = totals[spot.file] ?? (0, 0)
            entry.ms += spot.milliseconds
            entry.count += 1
            totals[spot.file] = entry
        }
        return totals
            .map { (file: $0.key, totalMs: $0.value.ms, count: $0.value.count) }
            .sorted { $0.totalMs > $1.totalMs }
    }

    // MARK: - Formatting

    static func formatReport(
        hotspots: [Hotspot],
        thresholdMs: Int,
        limit: Int,
        buildSucceeded: Bool,
    ) -> String {
        var text = "## Compile Hotspots (threshold \(thresholdMs)ms)\n\n"

        if !buildSucceeded {
            text += "⚠️ The build did not succeed — results reflect only the warnings emitted "
                + "before it stopped.\n\n"
        }

        if hotspots.isEmpty {
            text += "No functions or expressions exceeded \(thresholdMs)ms to type-check. "
            text +=
                "Lower `threshold_ms` to surface more, or confirm the build actually recompiled "
            text += "(pass `clean: true`).\n"
            return text
        }

        text += "\(hotspots.count) hotspot\(hotspots.count == 1 ? "" : "s") above threshold.\n\n"

        text += "### Slowest declarations\n\n"

        for spot in hotspots.prefix(limit) {
            let ms = "\(spot.milliseconds)ms".padding(toLength: 8, withPad: " ", startingAt: 0)
            text += "  \(ms)[\(spot.kind.rawValue)] \(spot.file):\(spot.line):\(spot.column)\n"
        }

        let files = fileTotals(hotspots)

        if files.count > 1 {
            text += "\n### Costliest files\n\n"

            for entry in files.prefix(limit) {
                let ms = "\(entry.totalMs)ms".padding(toLength: 8, withPad: " ", startingAt: 0)
                text +=
                    "  \(ms)\(entry.file) (\(entry.count) hotspot\(entry.count == 1 ? "" : "s"))\n"
            }
        }

        return text
    }
}
