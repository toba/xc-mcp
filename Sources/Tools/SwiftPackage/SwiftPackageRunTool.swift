import Foundation
import MCP

public struct SwiftPackageRunTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager

    public init(swiftRunner: SwiftRunner = SwiftRunner(), sessionManager: SessionManager) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "swift_package_run",
            description:
                "Run an executable from a Swift package. Builds the package if needed and runs the specified executable.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified."
                        ),
                    ]),
                    "executable": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the executable to run. If not specified, runs the default executable."
                        ),
                    ]),
                    "arguments": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Arguments to pass to the executable."),
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

        // Get executable name if specified
        let executable: String?
        if case let .string(value) = arguments["executable"] {
            executable = value
        } else {
            executable = nil
        }

        // Get arguments if specified
        var execArgs: [String] = []
        if case let .array(values) = arguments["arguments"] {
            for value in values {
                if case let .string(arg) = value {
                    execArgs.append(arg)
                }
            }
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
            let result = try await swiftRunner.runExecutable(
                packagePath: packagePath,
                executableName: executable,
                arguments: execArgs
            )

            if result.succeeded {
                var message = "Executable"
                if let executable {
                    message += " '\(executable)'"
                }
                message += " completed successfully"

                if !result.stdout.isEmpty {
                    message += "\n\nOutput:\n\(result.stdout)"
                }

                return CallTool.Result(
                    content: [.text(message)]
                )
            } else {
                throw MCPError.internalError(
                    "Execution failed (exit code \(result.exitCode)):\n\(result.output)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Execution failed: \(error.localizedDescription)")
        }
    }
}
