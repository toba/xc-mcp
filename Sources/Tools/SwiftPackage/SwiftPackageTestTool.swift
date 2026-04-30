import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct SwiftPackageTestTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_test",
            description:
            "Run tests for a Swift package. Supports filtering to run specific tests.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified.",
                        ),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Test filter pattern to run specific tests (e.g., 'MyTests' or 'MyTests/testMethod').",
                        ),
                    ]),
                    "skip": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Test filter pattern to exclude tests (e.g., 'SlowTests').",
                        ),
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
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for the test run. Defaults to 300 (5 minutes), or 900 (15 minutes) on a cold build cache.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let filter = arguments.getString("filter")
        let skip = arguments.getString("skip")
        let parallel: Bool? = if case let .bool(value) = arguments["parallel"] { value }
        else { nil }
        let explicitTimeout = arguments.getInt("timeout").map { Duration.seconds($0) }
        let isCold = SwiftRunner.isColdCache(packagePath: packagePath)
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

        // Stop any in-flight warmup so it doesn't race the user's invocation
        // on `.build/` (and so the BuildGuard flock is released promptly).
        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        do {
            let result = try await swiftRunner.test(
                packagePath: packagePath,
                filter: filter,
                skip: skip,
                parallel: parallel,
                environment: environment,
                timeout: timeout,
            )

            var context = "swift package"
            if let filter {
                context += " (filter: '\(filter)')"
            }
            if let skip {
                context += " (skip: '\(skip)')"
            }
            return try await ErrorExtractor.formatTestToolResult(
                output: result.output, succeeded: result.succeeded,
                context: context,
                projectRoot: packagePath,
            )
        } catch let ProcessError.timeout(duration) {
            var message =
                "swift test timed out after \(duration) (package: \(packagePath))."
            if explicitTimeout == nil, isCold {
                message +=
                    " Detected a cold SwiftPM cache; the cold-cache timeout (\(SwiftRunner.coldCacheTimeout)) was used."
            }
            message +=
                " Heavy dependency graphs (e.g. swift-syntax) can take longer than the default on a first build. Pass an explicit `timeout` (seconds) or run `swift_package_build` first to warm the cache."
            throw MCPError.internalError(message)
        } catch {
            throw error.asMCPError()
        }
    }
}
