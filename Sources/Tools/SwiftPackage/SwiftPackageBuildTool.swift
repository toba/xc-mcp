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
        .init(
            name: "swift_package_build",
            description:
                "Build a Swift package. Supports building specific products and configurations. Pass `destination` to cross-compile for another Apple platform, which is the only way to compile source behind `#if os(iOS)` or `#if canImport(UIKit)`.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration: 'debug' or 'release'. Defaults to 'debug'.",
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
                        "enum": .array(
                            SwiftBuildDestination.acceptedValues.map { Value.string($0) },
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for the build. Defaults to 300 (5 minutes), or 900 (15 minutes) on a cold build cache.",
                        ),
                    ]),
                ]),
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
        let requestedDestination = try SwiftBuildDestination.parse(from: arguments)
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let explicitTimeout = arguments.explicitTimeout()
        let isCold = SwiftRunner.isColdCache(
            packagePath: packagePath, destination: requestedDestination,
        )
        let timeout = explicitTimeout
            ?? (isCold ? SwiftRunner.coldCacheTimeout : SwiftRunner.defaultTimeout)

        // Verify Package.swift exists
        let packageSwiftPath = URL(fileURLWithPath: packagePath).appendingPathComponent(
            "Package.swift",
        ).path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw MCPError.invalidParams(
                "No Package.swift found at \(packagePath). Please provide a valid Swift package path.",
            )
        }

        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let destination = try await requestedDestination.resolve()
        let destinationLabel = SwiftBuildDestination.label(for: destination)
        let buildStart = ContinuousClock.now

        do {
            let result = try await swiftRunner.build(
                packagePath: packagePath,
                configuration: configuration,
                product: product,
                buildTests: buildTests,
                destination: destination,
                environment: environment,
                timeout: timeout,
                onProgress: onProgress,
            )

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                let elapsed = buildStart.duration(to: .now).elapsedDescription
                var message = "Build succeeded"
                if let product { message += " for product '\(product)'" }
                message += " (\(configuration) configuration, \(destinationLabel), \(elapsed))"

                return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)]
                )
            }

            // On compiler signal crash, retry with -v to surface the crashing file
            if let signal = ErrorExtractor.detectCompilerCrash(in: result.output) {
                let verboseResult = try await swiftRunner.build(
                    packagePath: packagePath,
                    configuration: configuration,
                    product: product,
                    buildTests: buildTests,
                    verbose: true,
                    destination: destination,
                    environment: environment,
                    timeout: timeout,
                )
                let crashDetails = ErrorExtractor.extractCrashDetails(
                    from: verboseResult.output, signal: signal,
                )
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError(
                    "Build failed for \(destinationLabel):\n\(errorOutput)\n\n\(crashDetails)",
                )
            }

            let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
            throw MCPError.internalError("Build failed for \(destinationLabel):\n\(errorOutput)")
        } catch let ProcessError.timeout(duration) {
            throw MCPError.internalError(
                SwiftRunner.timeoutMessage(
                    command: "swift build",
                    duration: duration,
                    packagePath: packagePath,
                    destination: destination,
                    usedColdCacheTimeout: explicitTimeout == nil && isCold,
                    advice: "Pass an explicit `timeout` (seconds) and retry.",
                ),
            )
        } catch {
            throw try error.asMCPError()
        }
    }
}
