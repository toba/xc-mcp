import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct SwiftPackageBuildTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_build",
            description:
            "Build a Swift package. Supports building specific products and configurations.",
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
                        "description": .string(
                            "Also build test targets. Defaults to false.",
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
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let explicitTimeout = arguments.getInt("timeout").map { Duration.seconds($0) }
        let isCold = SwiftRunner.isColdCache(packagePath: packagePath)
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

        do {
            let result = try await swiftRunner.build(
                packagePath: packagePath,
                configuration: configuration,
                product: product,
                buildTests: buildTests,
                environment: environment,
                timeout: timeout,
                onProgress: onProgress,
            )

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                var message = "Build succeeded"
                if let product {
                    message += " for product '\(product)'"
                }
                message += " (\(configuration) configuration)"

                return CallTool.Result(
                    content: [.text(text: message, annotations: nil, _meta: nil)],
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
                    environment: environment,
                    timeout: timeout,
                )
                let crashDetails = ErrorExtractor.extractCrashDetails(
                    from: verboseResult.output, signal: signal,
                )
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError("Build failed:\n\(errorOutput)\n\n\(crashDetails)")
            }

            let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
            throw MCPError.internalError("Build failed:\n\(errorOutput)")
        } catch let ProcessError.timeout(duration) {
            var message =
                "swift build timed out after \(duration) (package: \(packagePath))."
            if explicitTimeout == nil, isCold {
                message +=
                    " Detected a cold SwiftPM cache; the cold-cache timeout (\(SwiftRunner.coldCacheTimeout)) was used."
            }
            message +=
                " Heavy dependency graphs (e.g. swift-syntax) can take longer than the default on a first build. Pass an explicit `timeout` (seconds) and retry."
            throw MCPError.internalError(message)
        } catch {
            throw try error.asMCPError()
        }
    }
}
