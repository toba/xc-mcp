import MCP
import XCMCPCore
import Foundation

public struct CleanTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "clean",
            description:
            "Clean build products using xcodebuild's native clean action. Removes build artifacts to ensure fresh builds.",
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
                            "The scheme to clean. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                    "derived_data": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Also delete DerivedData for this project. Removes both xc-mcp's scoped DerivedData (under ~/Library/Caches/xc-mcp/DerivedData, used by build/test tools) and matching entries in Xcode's standard DerivedData location. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let cleanDerivedData = arguments.getBool("derived_data")

        do {
            let result = try await xcodebuildRunner.clean(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            var messages: [String] = []

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                messages.append(
                    "Clean succeeded for scheme '\(scheme)' (\(configuration) configuration)",
                )

                // Clean derived data if requested
                if cleanDerivedData {
                    let derivedDataResult = cleanDerivedDataDirectory(
                        projectPath: projectPath, workspacePath: workspacePath,
                    )
                    messages.append(derivedDataResult)
                }

                return CallTool.Result(
                    content: [.text(
                        text: messages.joined(separator: "\n"),
                        annotations: nil,
                        _meta: nil,
                    )],
                )
            } else {
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError("Clean failed:\n\(errorOutput)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }

    private func cleanDerivedDataDirectory(projectPath: String?, workspacePath: String?)
        -> String
    {
        // Get the project/workspace name to find the specific derived data folder
        let projectName: String
        if let workspacePath {
            projectName =
                URL(fileURLWithPath: workspacePath).lastPathComponent.replacingOccurrences(
                    of: ".xcworkspace", with: "",
                )
        } else if let projectPath {
            projectName =
                URL(fileURLWithPath: projectPath).lastPathComponent.replacingOccurrences(
                    of: ".xcodeproj", with: "",
                )
        } else {
            return "Could not determine project name for DerivedData cleanup"
        }

        var deleted: [String] = []
        var failures: [String] = []

        // 1) Clean the scoped DerivedData path that xc-mcp's own builds actually use.
        //    Without this, `clean(derived_data: true)` clears Xcode's standard location
        //    while subsequent `build_macos`/`test_macos` invocations keep reading stale
        //    artifacts (notably macro plugin expansions) from the scoped cache.
        if let scoped = DerivedDataScoper.effectivePath(
            workspacePath: workspacePath,
            projectPath: projectPath,
        ) {
            if FileManager.default.fileExists(atPath: scoped) {
                if let err = removePath(scoped) {
                    failures.append("\(scoped): \(err)")
                } else {
                    deleted.append(scoped)
                }
            }
        }

        // 2) Also clean Xcode's standard DerivedData entries for this project, since
        //    the user may have built via Xcode in parallel.
        let xcodeDerivedData = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: xcodeDerivedData) {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: xcodeDerivedData)
                for item in contents
                    where item.hasPrefix(projectName + "-") || item == projectName
                {
                    let fullPath = xcodeDerivedData + "/" + item
                    if let err = removePath(fullPath) {
                        failures.append("\(item): \(err)")
                    } else {
                        deleted.append(item)
                    }
                }
            } catch {
                failures.append("listing Xcode DerivedData: \(error.localizedDescription)")
            }
        }

        var lines: [String] = []
        if deleted.isEmpty {
            lines.append("No DerivedData found for '\(projectName)'")
        } else {
            lines.append("Deleted DerivedData: \(deleted.joined(separator: ", "))")
        }
        if !failures.isEmpty {
            lines.append("Failures: \(failures.joined(separator: "; "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Removes a path, falling back to `rm -rf` when `FileManager` hits a permissions
    /// edge case. Returns `nil` on success or a human-readable error message.
    private func removePath(_ path: String) -> String? {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(atPath: path)
            return nil
        } catch {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/rm")
            process.arguments = ["-rf", path]
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
                    ? nil
                    : "rm -rf exited \(process.terminationStatus)"
            } catch {
                return error.localizedDescription
            }
        }
    }
}
