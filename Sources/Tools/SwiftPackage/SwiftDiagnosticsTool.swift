import MCP
import XCMCPCore
import Foundation

public struct SwiftDiagnosticsTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "swift_diagnostics",
            description:
                "Collect all compiler warnings, errors, and lint violations for a Swift package. Performs a clean build so all diagnostics are emitted.",
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
                    "run_lint": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Run sm (swiftiomatic) lint after building to include style violations. Defaults to true.",
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
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let buildTests = arguments.getBool("build_tests", default: true)
        let runLint = arguments.getBool("run_lint", default: true)
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

            // Step 3: On compiler signal crash, retry with -v for verbose output
            var crashDetails: String?

            if let signal = ErrorExtractor.detectCompilerCrash(in: buildResult.output) {
                let verboseResult = try await swiftRunner.build(
                    packagePath: packagePath,
                    buildTests: buildTests,
                    verbose: true,
                    timeout: timeout,
                )
                crashDetails = ErrorExtractor.extractCrashDetails(
                    from: verboseResult.output, signal: signal,
                )
            }

            // Step 4: Parse build output for diagnostics
            let parsed = ErrorExtractor.parseBuildOutput(buildResult.output)
            let buildFailed = !buildResult.succeeded && parsed.status != "success"

            // Step 5: Optionally run sm lint
            var lintSection: String?
            if runLint { lintSection = await runSm(packagePath: packagePath) }

            // Step 6: Format combined output
            let output = formatDiagnostics(
                parsed: parsed, buildFailed: buildFailed,
                crashDetails: crashDetails, lintSection: lintSection,
            )

            if buildFailed { throw MCPError.internalError(output) }

            return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
        } catch {
            throw try error.asMCPError()
        }
    }

    private func formatDiagnostics(
        parsed: BuildResult,
        buildFailed: Bool,
        crashDetails: String? = nil,
        lintSection: String?,
    ) -> String {
        var sections: [String] = []

        // Build diagnostics section
        let hasWarnings = !parsed.warnings.isEmpty
        let hasErrors = !parsed.errors.isEmpty || !parsed.linkerErrors.isEmpty

        if hasWarnings || hasErrors || buildFailed {
            let header = BuildResultFormatter.formatBuildResult(parsed)
            sections.append("## Build Diagnostics\n\n\(header)")
        }

        // Compiler crash details from verbose retry
        if let crashDetails { sections.append("## Compiler Crash\n\n\(crashDetails)") }

        // Lint section
        if let lintSection { sections.append("## Lint Violations\n\n\(lintSection)") }

        return sections.isEmpty
            ? "No build warnings or lint violations found. Code is clean!"
            : sections.joined(separator: "\n\n")
    }

    private func runSm(packagePath: String) async -> String? {
        guard let executablePath = try? await BinaryLocator.find("sm") else { return nil }

        let args: [String] = [
            "lint", "--reporter", "json", "--parallel", "--recursive", packagePath,
        ]

        guard let result = try? await ProcessResult.run(
            executablePath, arguments: args, mergeStderr: false,
        ) else { return nil }

        let violations = SwiftLintTool.parseJSONOutput(result.stdout)
        return violations.isEmpty ? nil : SwiftLintTool.formatViolations(violations)
    }
}
