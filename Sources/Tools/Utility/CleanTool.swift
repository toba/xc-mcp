import MCP
import XCMCPCore
import Foundation

public struct CleanTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(), sessionManager: SessionManager,
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "clean",
            description:
            "Clean build products using xcodebuild's native clean action. Removes build artifacts to ensure fresh builds.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to clean. Uses session default if not specified.",
                        ),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug.",
                        ),
                    ]),
                    "derived_data": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Also delete DerivedData for this project. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let (projectPath, workspacePath) = try await sessionManager.resolveBuildPaths(
            from: arguments,
        )
        let scheme = try await sessionManager.resolveScheme(from: arguments)
        let configuration = await sessionManager.resolveConfiguration(from: arguments)
        let cleanDerivedData = arguments.getBool("derived_data")

        do {
            let result = try await xcodebuildRunner.clean(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration,
            )

            var messages: [String] = []

            let buildResult = ErrorExtractor.parseBuildOutput(result.output)

            if result.succeeded || buildResult.status == "success" {
                messages.append(
                    "Clean succeeded for scheme '\(scheme)' (\(configuration) configuration)",
                )

                // Clean derived data if requested
                if cleanDerivedData {
                    let derivedDataResult = cleanDerivedDataDirectory(
                        projectPath: projectPath, workspacePath: workspacePath,
                    )
                    messages.append(derivedDataResult)
                }

                return CallTool.Result(
                    content: [.text(messages.joined(separator: "\n"))],
                )
            } else {
                let errorOutput = BuildResultFormatter.formatBuildResult(buildResult)
                throw MCPError.internalError("Clean failed:\n\(errorOutput)")
            }
        } catch {
            throw error.asMCPError()
        }
    }

    private func cleanDerivedDataDirectory(projectPath: String?, workspacePath: String?)
        -> String
    {
        // Get the default DerivedData path
        let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"

        // Get the project/workspace name to find the specific derived data folder
        let projectName: String
        if let workspacePath {
            projectName =
                URL(fileURLWithPath: workspacePath).lastPathComponent.replacingOccurrences(
                    of: ".xcworkspace", with: "",
                )
        } else if let projectPath {
            projectName =
                URL(fileURLWithPath: projectPath).lastPathComponent.replacingOccurrences(
                    of: ".xcodeproj", with: "",
                )
        } else {
            return "Could not determine project name for DerivedData cleanup"
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: derivedDataPath) else {
            return "DerivedData directory does not exist"
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: derivedDataPath)
            var deletedPaths: [String] = []

            for item in contents {
                // DerivedData folders are named like "ProjectName-hashstring"
                if item.hasPrefix(projectName + "-") || item == projectName {
                    let fullPath = derivedDataPath + "/" + item
                    try fileManager.removeItem(atPath: fullPath)
                    deletedPaths.append(item)
                }
            }

            if deletedPaths.isEmpty {
                return "No DerivedData found for '\(projectName)'"
            } else {
                return "Deleted DerivedData: \(deletedPaths.joined(separator: ", "))"
            }
        } catch {
            return "Failed to clean DerivedData: \(error.localizedDescription)"
        }
    }
}
