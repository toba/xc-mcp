import Foundation
import MCP
import XCMCPCore

public struct SwiftPackageListTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_list",
            description:
                "List dependencies for a Swift package. Shows the dependency tree including resolved versions.",
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
            let result = try await swiftRunner.showDependencies(packagePath: packagePath)

            if result.succeeded {
                var message = "Package dependencies:\n"
                if result.stdout.isEmpty {
                    message += "(No dependencies)"
                } else {
                    message += result.stdout
                }

                return CallTool.Result(
                    content: [.text(message)]
                )
            } else {
                throw MCPError.internalError("Failed to list dependencies:\n\(result.output)")
            }
        } catch {
            throw error.asMCPError()
        }
    }
}
