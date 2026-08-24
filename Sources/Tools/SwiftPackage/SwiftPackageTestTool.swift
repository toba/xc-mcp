import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct SwiftPackageTestTool: Sendable {
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
                    "Build configuration: 'debug' or 'release'. Defaults to 'debug'. Use 'release' to reproduce a bug that only appears under optimization; -enable-testing is passed for you, so @testable imports still resolve.",
                ),
                "enum": .array([.string("debug"), .string("release")]),
            ]),
            "filter": .object([
                "type": .string("string"),
                "description": .string(
                    "Test filter pattern to run specific tests (e.g., 'MyTests' or 'MyTests/testMethod').",
                ),
            ]),
            "skip": .object([
                "type": .string("string"),
                "description": .string("Test filter pattern to exclude tests (e.g., 'SlowTests')."),
            ]),
            "parallel": .object([
                "type": .string("boolean"),
                "description": .string(
                    "Control test parallelism. True for --parallel, false for --no-parallel. Omit for default behavior.",
                ),
            ]),
            "env": .object([
                "type": .string("object"),
                "description": .string(
                    "Environment variables to set for the test run (e.g., {\"RUN_SLOW_TESTS\": \"1\"}).",
                ),
                "additionalProperties": .object(["type": .string("string")]),
            ]),
            "destination": .object([
                "type": .string("string"),
                "description": .string(
                    "Platform to compile the test targets for. Defaults to 'macos', which runs the tests on the host. Any other value builds the test targets for that platform and runs nothing, because SwiftPM cannot execute a cross-compiled test bundle. A simulator destination needs no booted simulator.",
                ),
                "enum": .array(SwiftBuildDestination.acceptedValues.map { Value.string($0) }),
            ]),
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }
        properties.merge(SwiftPackageToolSchema.timeout(for: "the test run")) { current, _ in
            current
        }
        properties.merge(SwiftDiagnosticOptions.schemaProperties) { current, _ in current }

        return .init(
            name: "swift_package_test",
            description:
                "Run tests for a Swift package. Supports filtering to run specific tests. Pass `configuration: release` to reproduce an optimizer-only bug. Pass `destination` to compile the test targets for another Apple platform instead; SwiftPM cannot execute a cross-compiled test bundle, so that mode is a compile check.",
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
        let filter = arguments.getString("filter")
        let skip = arguments.getString("skip")
        let parallel: Bool? =
            if case let .bool(value) = arguments["parallel"] { value } else { nil }
        let requestedDestination = try SwiftBuildDestination.parse(from: arguments)
        let explicitTimeout = arguments.explicitTimeout()
        let diagnostics = SwiftDiagnosticOptions(from: arguments)
        let isCold = SwiftRunner.isColdCache(
            packagePath: packagePath, destination: requestedDestination,
            configuration: configuration,
        )
        let timeout = explicitTimeout
            ?? (isCold ? SwiftRunner.coldCacheTimeout : SwiftRunner.defaultTimeout)

        // Merge session env with per-invocation env (per-invocation wins)
        let environment = await sessionManager.resolveEnvironment(from: arguments)

        // Verify Package.swift exists
        let packageSwiftPath = URL(fileURLWithPath: packagePath).appendingPathComponent(
            "Package.swift",
        ).path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw MCPError.invalidParams(
                "No Package.swift found at \(packagePath). Please provide a valid Swift package path.",
            )
        }

        // Stop any in-flight warmup so it doesn't race the user's invocation on `.build/` (and so
        // the BuildGuard flock is released promptly).
        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let testStart = ContinuousClock.now
        let sink = try diagnostics.makeSink()
        // Pairing the close with the open covers every exit path. The destination resolution below
        // throws outside every catch here, and it used to leave the file handle open.
        defer { _ = sink?.finish() }
        let progress = SwiftDiagnosticOptions.combine(onProgress, sink)

        // SwiftPM builds a cross-compiled test bundle but cannot execute it on the host, so a
        // non-host destination becomes a `--build-tests` compile check.
        if let destination = try await requestedDestination.resolve() {
            return try await buildTestsOnly(
                packagePath: packagePath,
                configuration: configuration,
                destination: destination,
                filter: filter,
                skip: skip,
                swiftcFlags: diagnostics.swiftcFlags,
                environment: environment,
                explicitTimeout: explicitTimeout,
                timeout: timeout,
                start: testStart,
                sink: sink,
                onProgress: progress,
            )
        }

        do {
            let result = try await swiftRunner.test(
                packagePath: packagePath,
                configuration: configuration,
                filter: filter,
                skip: skip,
                parallel: parallel,
                swiftcFlags: diagnostics.swiftcFlags,
                environment: environment,
                timeout: timeout,
                onProgress: progress,
            )
            let sinkSummary = sink?.finish()

            var context = "swift package (\(SwiftBuildDestination.hostLabel), \(configuration))"
            if let filter { context += " (filter: '\(filter)')" }
            if let skip { context += " (skip: '\(skip)')" }
            if let sinkSummary {
                context += " (\(sinkSummary.linesWritten) lines streamed to \(sinkSummary.path))"
            }
            return try await ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: context,
                projectRoot: packagePath,
                wallClock: testStart.duration(to: .now),
                termination: result.termination,
                settledAfterCompletion: result.settledAfterCompletion,
            )
        } catch let ProcessError.timeout(duration) {
            throw MCPError.internalError(SwiftRunner.timeoutMessage(
                command: "swift test", duration: duration, packagePath: packagePath,
                destination: nil, usedColdCacheTimeout: explicitTimeout == nil && isCold,
                advice: Self.timeoutAdvice,
            ))
        } catch {
            throw try error.asMCPError()
        }
    }

    /// Compiles the test targets for a cross-compilation destination without running them.
    ///
    /// SwiftPM produces a test bundle for the target platform, and the host cannot execute it. The
    /// build is still the check a cross-platform library needs, because it is the only thing that
    /// compiles test code guarded by `#if os(iOS)`.
    private func buildTestsOnly(
        packagePath: String,
        configuration: String,
        destination: ResolvedSwiftDestination,
        filter: String?,
        skip: String?,
        swiftcFlags: [String],
        environment: Environment,
        explicitTimeout: Duration?,
        timeout: Duration,
        start: ContinuousClock.Instant,
        sink: StreamedOutputSink?,
        onProgress: (@Sendable (String) -> Void)?,
    ) async throws -> CallTool.Result {
        do {
            let result = try await swiftRunner.build(
                packagePath: packagePath,
                configuration: configuration,
                buildTests: true,
                destination: destination,
                swiftcFlags: swiftcFlags,
                environment: environment,
                timeout: timeout,
                onProgress: onProgress,
            )
            let sinkSummary = sink?.finish()

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)
            guard result.succeeded || buildResult.status == "success" else {
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError(
                    "Test targets failed to build for \(destination.label):\n\(errorOutput)",
                )
            }

            let elapsed = start.duration(to: .now).elapsedDescription
            var message = "Test targets built for \(destination.label) "
            message += "(\(configuration) configuration, \(elapsed)). "
            message +=
                "No test ran: SwiftPM cannot execute a test bundle built for another platform. "
            message += "Omit `destination` to run the tests on the host."
            if filter != nil || skip != nil {
                message += " `filter` and `skip` select tests to run, so they had no effect here."
            }
            if let sinkSummary { message += "\n\n\(sinkSummary.formatted())" }
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch let ProcessError.timeout(duration) {
            throw MCPError.internalError(SwiftRunner.timeoutMessage(
                command: "swift build --build-tests", duration: duration, packagePath: packagePath,
                destination: destination, usedColdCacheTimeout: explicitTimeout == nil,
                advice: Self.timeoutAdvice,
            ))
        } catch {
            throw try error.asMCPError()
        }
    }

    /// The closing sentence of every timeout error this tool reports.
    private static let timeoutAdvice =
        "Pass an explicit `timeout` (seconds) or run `swift_package_build` first to warm the cache."
}
