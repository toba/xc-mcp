import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct SwiftPackageBuildTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "configuration": .object([
                "type": .string("string"),
                "description": .string(
                    "Build configuration: 'debug' or 'release'. Defaults to 'debug'. A release build with build_tests also passes -enable-testing, which @testable imports need.",
                ),
                "enum": .array([.string("debug"), .string("release")]),
            ]),
            "product": .object([
                "type": .string("string"),
                "description": .string(
                    "Specific product to build. If not specified, builds all products.",
                ),
            ]),
            "build_tests": .object([
                "type": .string("boolean"),
                "description": .string("Also build test targets. Defaults to false."),
            ]),
            "destination": .object([
                "type": .string("string"),
                "description": .string(
                    "Platform to compile for. Defaults to 'macos', the host. A simulator destination needs no booted simulator, and it is the way to compile iOS-conditional source in a cross-platform package.",
                ),
                "enum": .array(SwiftBuildDestination.acceptedValues.map { Value.string($0) }),
            ]),
        ]
        properties.merge([String: Value].errorsOnlySchemaProperty()) { current, _ in current }
        properties.merge([String: Value].continueBuildingSchemaProperty) { current, _ in current }
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }
        properties.merge(SwiftPackageToolSchema.timeout(for: "the build")) { current, _ in current }
        properties.merge(SwiftDiagnosticOptions.schemaProperties) { current, _ in current }
        properties.merge(SwiftBuildTraits.schemaProperties) { current, _ in current }

        return .init(
            name: "swift_package_build",
            description:
                "Build a Swift package. Supports building specific products and configurations. A failed build names every file the compiler reached, not the first failing one alone, so one call carries the whole repair list. Pass `errors_only` to leave the warnings out of that list. Pass `destination` to cross-compile for another Apple platform, which is the only way to compile source behind `#if os(iOS)` or `#if canImport(UIKit)`. Pass `traits` to enable package traits, which is the only way to compile source behind `#if <TraitName>`; `swiftc_flags` is not a substitute for it. Pass `swiftc_flags` to run a compiler probe without editing Package.swift.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let configuration = arguments.getString("configuration") ?? "debug"
        let product = arguments.getString("product")
        let buildTests = arguments.getBool("build_tests")
        let errorsOnly = arguments.getBool("errors_only")
        let continueAfterErrors = arguments.getBool("continue_building_after_errors", default: true)
        let requestedDestination = try SwiftBuildDestination.parse(from: arguments)
        let traits = try await sessionManager.resolveTraits(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let explicitTimeout = arguments.explicitTimeout()
        let diagnostics = SwiftDiagnosticOptions(from: arguments)
        let isCold = SwiftRunner.isColdCache(
            packagePath: packagePath, destination: requestedDestination,
            configuration: configuration,
        )
        let timeout = explicitTimeout
            ?? (isCold ? SwiftRunner.coldCacheTimeout : SwiftRunner.defaultTimeout)

        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let destination = try await requestedDestination.resolve()
        let destinationLabel = SwiftBuildDestination.label(for: destination)
        let buildStart = ContinuousClock.now

        let sink = try diagnostics.makeSink()
        // Pairing the close with the open covers every exit path, including one a later edit adds.
        // A second finish() is a no-op, so the summary calls below stay as they are.
        defer { _ = sink?.finish() }
        let progress = SwiftDiagnosticOptions.combine(onProgress, sink)

        do {
            let result = try await swiftRunner.build(
                packagePath: packagePath,
                configuration: configuration,
                product: product,
                buildTests: buildTests,
                destination: destination,
                traits: traits,
                swiftcFlags: diagnostics.swiftcFlags,
                continueAfterErrors: continueAfterErrors,
                environment: environment,
                timeout: timeout,
                onProgress: progress,
            )
            let sinkSummary = sink?.finish()

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                let elapsed = buildStart.duration(to: .now).elapsedDescription
                var message = "Build succeeded"
                if let product { message += " for product '\(product)'" }
                message +=
                    " (\(configuration) configuration, \(destinationLabel), \(traits.label), \(elapsed))"
                if let warning = traits.replacedDefaultsWarning { message += "\n\n\(warning)" }
                if let sinkSummary { message += "\n\n\(sinkSummary.formatted())" }

                return CallTool.Result.text(message)
            }

            var errorOutput = BuildResultFormatter.formatBuildResult(
                buildResult, projectRoot: packagePath, errorsOnly: errorsOnly,
            )
            if let sinkSummary { errorOutput += "\n\n\(sinkSummary.formatted())" }

            // On compiler signal crash, retry with -v to surface the crashing file
            if let signal = ErrorExtractor.detectCompilerCrash(in: result.output) {
                errorOutput += "\n\n"
                    + (try await swiftRunner.diagnoseCompilerCrash(
                        signal: signal,
                        firstAttemptOutput: result.output,
                        packagePath: packagePath,
                        configuration: configuration,
                        product: product,
                        buildTests: buildTests,
                        destination: destination,
                        traits: traits,
                        swiftcFlags: diagnostics.swiftcFlags,
                        environment: environment,
                        timeout: timeout,
                    ))
            }
            throw MCPError.internalError(
                "Build failed for \(destinationLabel) with \(traits.label):\n\(errorOutput)",
            )
        } catch let ProcessError.timeout(duration) {
            throw MCPError.internalError(SwiftRunner.timeoutMessage(
                command: "swift build", duration: duration, packagePath: packagePath,
                destination: destination, usedColdCacheTimeout: explicitTimeout == nil && isCold,
                advice: "Pass an explicit `timeout` (seconds) and retry.",
            ))
        } catch {
            throw try error.asMCPError()
        }
    }
}
