import MCP
import XCMCPCore
import Foundation

public struct SwiftPackageListTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for listing dependencies. Defaults to 300 (5 minutes).",
                ),
            ])
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }

        return .init(
            name: "swift_package_list",
            description:
                "List dependencies for a Swift package. Shows the dependency tree including resolved versions.",
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

        let timeout = arguments.resolveTimeout(default: SwiftRunner.defaultTimeout)

        do {
            let result = try await swiftRunner.showDependencies(
                packagePath: packagePath,
                timeout: timeout,
            )

            if result.succeeded {
                var message = "Package dependencies:\n"

                if result.stdout.isEmpty {
                    message += "(No dependencies)"
                } else {
                    message += result.stdout
                }

                return CallTool.Result.text(message)
            } else {
                throw MCPError.internalError("Failed to list dependencies:\n\(result.output)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
