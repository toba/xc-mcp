import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct SwiftPackageRunTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "executable": .object([
                "type": .string("string"),
                "description": .string(
                    "Name of the executable to run. If not specified, runs the default executable.",
                ),
            ]),
            "arguments": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")]),
                "description": .string("Arguments to pass to the executable."),
            ]),
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for the run. Defaults to 300 (5 minutes).",
                ),
            ]),
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }

        return .init(
            name: "swift_package_run",
            description:
                "Run an executable from a Swift package. Builds the package if needed and runs the specified executable.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)

        // Get executable name if specified
        let executable = arguments.getString("executable")

        // Get arguments if specified
        let execArgs = arguments.getStringArray("arguments")
        let environment = await sessionManager.resolveEnvironment(from: arguments)
        let timeout = arguments.resolveTimeout(default: SwiftRunner.defaultTimeout)

        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        do {
            let result = try await swiftRunner.runExecutable(
                packagePath: packagePath,
                executableName: executable,
                arguments: execArgs,
                environment: environment,
                timeout: timeout,
            )

            if result.succeeded {
                var message = "Executable"
                if let executable { message += " '\(executable)'" }
                message += " completed successfully"

                if !result.stdout.isEmpty { message += "\n\nOutput:\n\(result.stdout)" }

                return CallTool.Result.text(message)
            } else {
                throw MCPError.internalError(
                    "Execution failed (exit code \(result.exitCode)):\n\(result.output)",
                )
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
