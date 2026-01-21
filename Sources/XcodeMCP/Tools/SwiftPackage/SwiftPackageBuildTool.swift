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

        // Get configuration
        let configuration: String
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else {
            configuration = "debug"
        }

        // Get product if specified
        let product: String?
        if case let .string(value) = arguments["product"] {
            product = value
        } else {
            product = nil
        }

        // Verify Package.swift exists
        let packageSwiftPath = (packagePath as NSString).appendingPathComponent("Package.swift")
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
                if let product = product {
                    message += " for product '\(product)'"
                }
                message += " (\(configuration) configuration)"

                return CallTool.Result(
                    content: [.text(message)]
                )
            } else {
                let errorOutput = extractBuildErrors(from: result.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Build failed: \(error.localizedDescription)")
        }
    }

    private func extractBuildErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("Build failed")
        }

        if errorLines.isEmpty {
            return lines.suffix(30).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }
}
