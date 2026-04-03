import MCP
import XCMCPCore
import Foundation

public struct DiagnosticsTool: Sendable {
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
            name: "diagnostics",
            description:
            "Collect all compiler warnings, errors, and lint violations for an Xcode project. Performs a clean build so all diagnostics are emitted.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(
                    [
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
                            "description": .string(
                                "Build configuration (Debug or Release). Defaults to Debug.",
                            ),
                        ]),
                        "include_lint": .object([
                            "type": .string("boolean"),
                            "description": .string(
                                "Run swiftlint after building to include style violations. Defaults to true.",
                            ),
                        ]),
                        "timeout": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Maximum time in seconds for the build. Defaults to 300 (5 minutes).",
                            ),
                        ]),
                    ].merging([String: Value].enableSanitizersSchemaProperty) { _, new in new },
                ),
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
        let includeLint = arguments.getBool("include_lint", default: true)
        let timeout =
            arguments.getInt("timeout").map { TimeInterval($0) }
                ?? XcodebuildRunner.defaultTimeout

        let projectRoot = ErrorExtractor.projectRoot(
            projectPath: projectPath, workspacePath: workspacePath,
        )

        do {
            // Step 1: Clean to force full recompilation
            _ = try await xcodebuildRunner.clean(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            // Step 2: Build with macOS destination
            let buildOutput: XcodebuildResult
            var timedOut = false
            do {
                let hasExplicitTimeout = arguments["timeout"] != nil
                buildOutput = try await xcodebuildRunner.build(
                    projectPath: projectPath,
                    workspacePath: workspacePath,
                    scheme: scheme,
                    destination: "platform=macOS",
                    configuration: configuration,
                    additionalArguments: arguments.enableSanitizersArgs(),
                    timeout: timeout,
                    outputTimeout: hasExplicitTimeout ? nil : XcodebuildRunner.outputTimeout,
                )
            } catch let error as XcodebuildError {
                // On timeout, use partial output for diagnostics instead of failing
                buildOutput = XcodebuildResult(
                    exitCode: 1, stdout: error.partialOutput, stderr: "",
                )
                timedOut = true
            }

            // Step 3: Parse build output for diagnostics
            let parsed = ErrorExtractor.parseBuildOutput(buildOutput.output)
            let buildFailed = timedOut || (!buildOutput.succeeded && parsed.status != "success")

            // Step 4: Optionally run swiftlint
            var lintSection: String?
            if includeLint, let root = projectRoot {
                lintSection = await runSwiftLint(projectRoot: root)
            }

            // Step 5: Format combined output
            var output = formatDiagnostics(
                parsed: parsed, buildFailed: buildFailed, timedOut: timedOut,
                lintSection: lintSection,
            )

            if timedOut {
                output =
                    "Build timed out after \(Int(timeout)) seconds. Partial diagnostics from output collected before timeout:\n\n"
                        + output
            }

            if buildFailed {
                throw MCPError.internalError(output)
            }

            return CallTool.Result(content: [.text(output)])
        } catch {
            throw error.asMCPError()
        }
    }

    private func formatDiagnostics(
        parsed: BuildResult, buildFailed: Bool, timedOut: Bool = false, lintSection: String?,
    ) -> String {
        var sections: [String] = []

        // Build diagnostics section
        // Don't pass projectRoot to formatBuildResult — it suppresses warning
        // details on success. Instead we always want details for diagnostics.
        let hasWarnings = !parsed.warnings.isEmpty
        let hasErrors = !parsed.errors.isEmpty || !parsed.linkerErrors.isEmpty

        if hasWarnings || hasErrors || buildFailed {
            let header = BuildResultFormatter.formatBuildResult(
                parsed, showWarnings: true,
                statusOverride: timedOut ? "Build interrupted (did not complete)" : nil,
            )
            sections.append("## Build Diagnostics\n\n\(header)")
        }

        // Lint section
        if let lintSection {
            sections.append("## Lint Violations\n\n\(lintSection)")
        }

        if sections.isEmpty {
            return "No build warnings or lint violations found. Code is clean!"
        }

        return sections.joined(separator: "\n\n")
    }

    private func runSwiftLint(projectRoot: String) async -> String? {
        guard let executablePath = try? await BinaryLocator.find("swiftlint") else {
            return nil
        }

        var args: [String] = ["lint", "--reporter", "json"]

        let configPath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(".swiftlint.yml").path
        if FileManager.default.fileExists(atPath: configPath) {
            args.append("--config")
            args.append(configPath)
        }

        args.append(projectRoot)

        guard
            let result = try? await ProcessResult.run(
                executablePath, arguments: args, mergeStderr: false,
            )
        else {
            return nil
        }

        let violations = SwiftLintTool.parseJSONOutput(result.stdout)
        if violations.isEmpty {
            return nil
        }

        return SwiftLintTool.formatViolations(violations)
    }
}
