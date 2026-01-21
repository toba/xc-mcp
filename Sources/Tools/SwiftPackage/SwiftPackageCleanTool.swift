import Foundation
import XCMCPCore
import MCP

public struct SwiftPackageCleanTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_clean",
            description:
                "Clean build artifacts for a Swift package. Removes the .build directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified."
                        ),
                    ])
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get package path
        let packagePath: String
        if case let .string(value) = arguments["package_path"] {
            packagePath = value
        } else if let sessionPackagePath = await sessionManager.packagePath {
            packagePath = sessionPackagePath
        } else {
            throw MCPError.invalidParams(
                "package_path is required. Set it with set_session_defaults or pass it directly.")
        }

        // Verify Package.swift exists
        let packageSwiftPath = URL(fileURLWithPath: packagePath).appendingPathComponent(
            "Package.swift"
        ).path
        guard FileManager.default.fileExists(atPath: packageSwiftPath) else {
            throw MCPError.invalidParams(
                "No Package.swift found at \(packagePath). Please provide a valid Swift package path."
            )
        }

        do {
            let result = try await swiftRunner.clean(packagePath: packagePath)

            if result.succeeded {
                return CallTool.Result(
                    content: [.text("Package cleaned successfully at \(packagePath)")]
                )
            } else {
                throw MCPError.internalError("Clean failed:\n\(result.output)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Clean failed: \(error.localizedDescription)")
        }
    }
}
