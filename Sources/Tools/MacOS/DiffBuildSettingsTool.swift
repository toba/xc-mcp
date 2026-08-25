import MCP
import XCMCPCore
import Foundation

/// Diffs the resolved build settings between two targets or configurations.
///
/// Runs `xcodebuild -showBuildSettings` for each and outputs only the settings that differ,
/// replacing the manual workflow of diffing two dumps by hand.
public struct DiffBuildSettingsTool: Sendable {
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
            name: "diff_build_settings",
            description:
                "Compare resolved build settings between two targets or two configurations "
                + "of the same target. Shows only the differences. Replaces the manual "
                + "workflow of running show_build_settings twice and diffing.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "target_a": .object([
                        "type": .string("string"),
                        "description": .string("First target name (or scheme name) to compare."),
                    ]),
                    "target_b": .object([
                        "type": .string("string"),
                        "description": .string("Second target name (or scheme name) to compare."),
                    ]),
                    "configuration_a": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Configuration for the first target. Defaults to Debug.",
                        ),
                    ]),
                    "configuration_b": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Configuration for the second target. Defaults to same as configuration_a.",
                        ),
                    ]),
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
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Only show settings whose keys contain this substring (case-insensitive). "
                                + "Example: 'SWIFT' to show only Swift-related differences.",
                        ),
                    ]),
                ]),
                "required": .array([.string("target_a"), .string("target_b")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let targetA = try arguments.getRequiredString("target_a")
        let targetB = try arguments.getRequiredString("target_b")
        let configA = arguments.getString("configuration_a") ?? "Debug"
        let configB = arguments.getString("configuration_b") ?? configA
        let filter = arguments.getString("filter")

        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )

        // Fetch both build settings concurrently
        async let settingsAResult = xcodebuildRunner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: targetA,
            configuration: configA,
            destination: XcodebuildRunner.macOSDestination,
        )
        async let settingsBResult = xcodebuildRunner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: targetB,
            configuration: configB,
            destination: XcodebuildRunner.macOSDestination,
        )

        let settingsA = try await BuildSettingExtractor.parseSettings(from: settingsAResult.stdout)
        let settingsB = try await BuildSettingExtractor.parseSettings(from: settingsBResult.stdout)

        // Find differences
        let allKeys = Set(settingsA.keys).union(settingsB.keys).sorted()
        var diffs: [(key: String, valueA: String?, valueB: String?)] = []

        for key in allKeys {
            let valueA = settingsA[key]
            let valueB = settingsB[key]

            if valueA != valueB {
                if let filter, !key.localizedCaseInsensitiveContains(filter) { continue }
                diffs.append((key: key, valueA: valueA, valueB: valueB))
            }
        }

        // Format output
        let labelA = configA == configB
            ? targetA
            : "\(targetA) (\(configA))"
        let labelB = configA == configB
            ? targetB
            : "\(targetB) (\(configB))"

        var text = "## Build Settings Diff\n\n"
        text += "**A:** \(labelA)\n"
        text += "**B:** \(labelB)\n"

        if let filter { text += "**Filter:** \(filter)\n" }

        text += "\n"

        if diffs.isEmpty {
            text += "No differences found"
            if filter != nil { text += " (with current filter)" }
            text += "."
        } else {
            text += "\(diffs.count) setting(s) differ:\n\n"

            // Find max key length for alignment
            let maxKeyLen = min(diffs.map(\.key.count).max() ?? 0, 40)

            for diff in diffs {
                let paddedKey = diff.key.padding(toLength: maxKeyLen, withPad: " ", startingAt: 0)
                let aVal = diff.valueA ?? "(not set)"
                let bVal = diff.valueB ?? "(not set)"

                // Truncate long values for readability
                let aDisplay = aVal.count > 80 ? String(aVal.prefix(77)) + "..." : aVal
                let bDisplay = bVal.count > 80 ? String(bVal.prefix(77)) + "..." : bVal

                text += "  \(paddedKey)\n"
                text += "    A: \(aDisplay)\n"
                text += "    B: \(bDisplay)\n\n"
            }
        }

        return CallTool.Result.text(text)
    }
}
