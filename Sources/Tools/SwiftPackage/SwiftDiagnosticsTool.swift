import MCP
import XCMCPCore
import Foundation

public struct SwiftDiagnosticsTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_diagnostics",
            description:
            "Collect all compiler warnings, errors, and lint violations for a Swift package. "
                + "Performs a clean build to ensure all diagnostics are emitted (cached builds hide warnings). "
                + "Returns diagnostics even on successful builds.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified.",
                        ),
                    ]),
                    "build_tests": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Also build test targets to collect their diagnostics. Defaults to true.",
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
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let buildTests = arguments.getBool("build_tests", default: true)
        let includeLint = arguments.getBool("include_lint", default: true)
        let timeout = arguments.getInt("timeout").map { Duration.seconds($0) }
            ?? SwiftRunner.defaultTimeout

        // Verify Package.swift exists
        let packageSwiftPath = URL(fileURLWithPath: packagePath).appendingPathComponent(
            "Package.swift",
        ).path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw MCPError.invalidParams(
                "No Package.swift found at \(packagePath). Please provide a valid Swift package path.",
            )
        }

        do {
            // Step 1: Clean to force full recompilation
            _ = try await swiftRunner.clean(packagePath: packagePath)

            // Step 2: Build (with --build-tests if requested)
            let buildResult = try await swiftRunner.build(
                packagePath: packagePath,
                buildTests: buildTests,
                timeout: timeout,
            )

            // Step 3: Parse build output for diagnostics
            let parsed = ErrorExtractor.parseBuildOutput(buildResult.output)
            let buildFailed = !buildResult.succeeded && parsed.status != "success"

            // Step 4: Optionally run swiftlint
            var lintSection: String?
            if includeLint {
                lintSection = await runSwiftLint(packagePath: packagePath)
            }

            // Step 5: Format combined output
            let output = formatDiagnostics(
                parsed: parsed, buildFailed: buildFailed, lintSection: lintSection,
            )

            if buildFailed {
                throw MCPError.internalError(output)
            }

            return CallTool.Result(content: [.text(output)])
        } catch {
            throw error.asMCPError()
        }
    }

    private func formatDiagnostics(
        parsed: BuildResult, buildFailed: Bool, lintSection: String?,
    ) -> String {
        var sections: [String] = []

        // Build diagnostics section
        let hasWarnings = !parsed.warnings.isEmpty
        let hasErrors = !parsed.errors.isEmpty || !parsed.linkerErrors.isEmpty

        if hasWarnings || hasErrors || buildFailed {
            let header = BuildResultFormatter.formatBuildResult(parsed)
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

    private func runSwiftLint(packagePath: String) async -> String? {
        guard let executablePath = try? await BinaryLocator.find("swiftlint") else {
            return nil
        }

        var args: [String] = ["lint", "--reporter", "json"]

        let configPath = URL(fileURLWithPath: packagePath)
            .appendingPathComponent(".swiftlint.yml").path
        if FileManager.default.fileExists(atPath: configPath) {
            args.append("--config")
            args.append(configPath)
        }

        args.append(packagePath)

        guard let result = try? await ProcessResult.run(
            executablePath, arguments: args, mergeStderr: false,
        ) else {
            return nil
        }

        let violations = SwiftLintTool.parseJSONOutput(result.stdout)
        if violations.isEmpty {
            return nil
        }

        return SwiftLintTool.formatViolations(violations)
    }
}
