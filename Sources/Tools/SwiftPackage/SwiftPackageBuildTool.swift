import Foundation
import MCP

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
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified."
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration: 'debug' or 'release'. Defaults to 'debug'."),
                        "enum": .array([.string("debug"), .string("release")]),
                    ]),
                    "product": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Specific product to build. If not specified, builds all products."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let configuration = arguments.getString("configuration") ?? "debug"
        let product = arguments.getString("product")

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
            let result = try await swiftRunner.build(
                packagePath: packagePath,
                configuration: configuration,
                product: product
            )

            if result.succeeded {
                var message = "Build succeeded"
                if let product {
                    message += " for product '\(product)'"
                }
                message += " (\(configuration) configuration)"

                return CallTool.Result(
                    content: [.text(message)]
                )
            } else {
                let errorOutput = ErrorExtractor.extractBuildErrors(from: result.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Build failed: \(error.localizedDescription)")
        }
    }
}
