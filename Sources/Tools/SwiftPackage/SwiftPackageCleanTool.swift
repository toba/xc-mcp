import MCP
import XCMCPCore
import Foundation

public struct SwiftPackageCleanTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = .init(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        .init(
            name: "swift_package_clean",
            description: "Clean build artifacts for a Swift package. Removes the .build directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(SwiftPackageToolSchema.packagePath),
                "required": .array([]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)

        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let cleanStart = ContinuousClock.now

        do {
            let result = try await swiftRunner.clean(packagePath: packagePath)

            if result.succeeded {
                let elapsed = cleanStart.duration(to: .now).elapsedDescription
                return CallTool.Result.text(
                    "Package cleaned successfully at \(packagePath) (\(elapsed))")
            } else {
                throw MCPError.internalError("Clean failed:\n\(result.output)")
            }
        } catch {
            throw try error.asMCPError()
        }
    }
}
