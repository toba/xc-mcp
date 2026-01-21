import Foundation
import MCP

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
                            "Path to the Swift package directory containing Package.swift. Uses session default if not specified."
                        ),
                    ]),
                    "filter": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Test filter pattern to run specific tests (e.g., 'MyTests' or 'MyTests/testMethod')."
                        ),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let filter = arguments.getString("filter")

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
            let result = try await swiftRunner.test(
                packagePath: packagePath,
                filter: filter
            )

            if result.succeeded {
                // Parse test results
                let summary = extractTestSummary(from: result.output)
                var message = "Tests passed"
                if let filter {
                    message += " (filter: '\(filter)')"
                }
                if !summary.isEmpty {
                    message += "\n\(summary)"
                }

                return CallTool.Result(
                    content: [.text(message)]
                )
            } else {
                let errorOutput = extractTestErrors(from: result.output)
                throw MCPError.internalError("Tests failed:\n\(errorOutput)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Test execution failed: \(error.localizedDescription)")
        }
    }

    private func extractTestSummary(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        // Look for test summary lines
        let summaryLines = lines.filter {
            $0.contains("Test Suite") || $0.contains("Executed")
                || $0.contains("passed") || $0.contains("failed")
        }
        return summaryLines.suffix(5).joined(separator: "\n")
    }

    private func extractTestErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("failed") || $0.contains("FAILED")
                || $0.contains("XCTAssert")
        }

        if errorLines.isEmpty {
            return lines.suffix(30).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }
}
