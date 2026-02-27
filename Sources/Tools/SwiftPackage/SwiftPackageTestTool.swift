import MCP
import XCMCPCore
import Subprocess
import Foundation

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
                            "Maximum time in seconds for the test run. Defaults to 300 (5 minutes).",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let filter = arguments.getString("filter")
        let skip = arguments.getString("skip")
        let parallel: Bool? = if case let .bool(value) = arguments["parallel"] { value }
        else { nil }
        let timeout = arguments.getInt("timeout").map { Duration.seconds($0) }
            ?? SwiftRunner.defaultTimeout

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
        } catch {
            throw error.asMCPError()
        }
    }
}
