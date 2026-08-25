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
        var properties: [String: Value] = [
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
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }
        properties.merge(SwiftBuildTraits.schemaProperties) { current, _ in current }

        return .init(
            name: "swift_diagnostics",
            description:
                "Collect all compiler warnings, errors, and lint violations for a Swift package. Performs a clean build so all diagnostics are emitted. Pass `traits` to cover source behind `#if <TraitName>`, which a default build never compiles and therefore never reports on.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let buildTests = arguments.getBool("build_tests", default: true)
        let runLint = arguments.getBool("run_lint", default: true)
        let traits = try await sessionManager.resolveTraits(from: arguments)
        let timeout = arguments.resolveTimeout(default: SwiftRunner.defaultTimeout)

        do {
            // Step 1: Clean to force full recompilation
            _ = try await swiftRunner.clean(packagePath: packagePath)

            // Step 2: Build (with --build-tests if requested)
            let buildResult = try await swiftRunner.build(
                packagePath: packagePath,
                buildTests: buildTests,
                traits: traits,
                timeout: timeout,
            )

            // Step 3: On compiler signal crash, retry with -v for verbose output
            var crashDetails: String?

            if let signal = ErrorExtractor.detectCompilerCrash(in: buildResult.output) {
                crashDetails = try await swiftRunner.diagnoseCompilerCrash(
                    signal: signal,
                    firstAttemptOutput: buildResult.output,
                    packagePath: packagePath,
                    buildTests: buildTests,
                    traits: traits,
                    timeout: timeout,
                )
            }

            // Step 4: Parse build output for diagnostics
            let parsed = ErrorExtractor.parseBuildOutput(buildResult.output)
            let buildFailed = !buildResult.succeeded && parsed.status != "success"

            // Step 5: Optionally run sm lint
            var lintSection: String?
            if runLint { lintSection = await SwiftLintTool.lintSection(forRoot: packagePath) }

            // Step 6: Format combined output
            let output = formatDiagnostics(
                parsed: parsed, buildFailed: buildFailed, traits: traits,
                crashDetails: crashDetails, lintSection: lintSection,
            )

            if buildFailed { throw MCPError.internalError(output) }

            return CallTool.Result.text(output)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Builds the report text.
    ///
    /// The trait set leads the report. A run that names no trait compiles none of the trait-gated
    /// source, so a bare "code is clean" line would claim coverage the build never had.
    private func formatDiagnostics(
        parsed: BuildResult,
        buildFailed: Bool,
        traits: SwiftBuildTraits,
        crashDetails: String? = nil,
        lintSection: String?,
    ) -> String {
        var sections = ["Built with \(traits.label)."]
        if let warning = traits.replacedDefaultsWarning { sections[0] += " \(warning)" }

        // Build diagnostics section
        let hasWarnings = !parsed.warnings.isEmpty
        let hasErrors = !parsed.errors.isEmpty || !parsed.linkerErrors.isEmpty

        if hasWarnings || hasErrors || buildFailed {
            let header = BuildResultFormatter.formatBuildResult(parsed)
            sections.append("## Build Diagnostics\n\n\(header)")
        }

        // Compiler crash details from verbose retry
        if let crashDetails { sections.append("## Compiler Crash\n\n\(crashDetails)") }

        // Lint section. The text carries its own heading, because the heading states whether sm
        // reported violations, failed, or never ran.
        if let lintSection { sections.append(lintSection) }

        if sections.count == 1 {
            sections.append("No build warnings or lint violations found. Code is clean!")
        }
        return sections.joined(separator: "\n\n")
    }
}
