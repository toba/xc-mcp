import Foundation
import XCMCPCore
import MCP

public struct BuildRunMacOSTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        sessionManager: SessionManager
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "build_run_macos",
            description:
                "Build and run an Xcode project or workspace on macOS. This combines build_macos and launch_mac_app into a single operation.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified."),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The scheme to build. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Architecture to build for (arm64 or x86_64). Defaults to the current machine's architecture."
                        ),
                    ]),
                    "args": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional arguments to pass to the app."),
                    ]),
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Get project/workspace path
        let projectPath: String?
        if case let .string(value) = arguments["project_path"] {
            projectPath = value
        } else {
            projectPath = await sessionManager.projectPath
        }

        let workspacePath: String?
        if case let .string(value) = arguments["workspace_path"] {
            workspacePath = value
        } else {
            workspacePath = await sessionManager.workspacePath
        }

        // Get scheme
        let scheme: String
        if case let .string(value) = arguments["scheme"] {
            scheme = value
        } else if let sessionScheme = await sessionManager.scheme {
            scheme = sessionScheme
        } else {
            throw MCPError.invalidParams(
                "scheme is required. Set it with set_session_defaults or pass it directly.")
        }

        // Get configuration
        let configuration: String
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else if let sessionConfig = await sessionManager.configuration {
            configuration = sessionConfig
        } else {
            configuration = "Debug"
        }

        // Get architecture (optional)
        let arch: String?
        if case let .string(value) = arguments["arch"] {
            arch = value
        } else {
            arch = nil
        }

        // Get optional launch arguments
        var launchArgs: [String] = []
        if case let .array(argsArray) = arguments["args"] {
            for arg in argsArray {
                if case let .string(argValue) = arg {
                    launchArgs.append(argValue)
                }
            }
        }

        // Validate we have either project or workspace
        if projectPath == nil && workspacePath == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly."
            )
        }

        do {
            var destination = "platform=macOS"
            if let arch {
                destination += ",arch=\(arch)"
            }

            // Step 1: Build
            let buildResult = try await xcodebuildRunner.build(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                destination: destination,
                configuration: configuration
            )

            if !buildResult.succeeded {
                let errorOutput = extractBuildErrors(from: buildResult.output)
                throw MCPError.internalError("Build failed:\n\(errorOutput)")
            }

            // Step 2: Get app path from build settings
            let buildSettings = try await xcodebuildRunner.showBuildSettings(
                projectPath: projectPath,
                workspacePath: workspacePath,
                scheme: scheme,
                configuration: configuration
            )

            guard let appPath = extractAppPath(from: buildSettings.stdout) else {
                throw MCPError.internalError(
                    "Could not determine app path from build settings.")
            }

            // Step 3: Launch app using open command
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

            var openArgs = [appPath]
            if !launchArgs.isEmpty {
                openArgs.append("--args")
                openArgs.append(contentsOf: launchArgs)
            }
            process.arguments = openArgs

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                var message = "Successfully built and launched '\(scheme)' on macOS"
                message += "\nApp path: \(appPath)"
                return CallTool.Result(content: [.text(message)])
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                throw MCPError.internalError("Failed to launch app: \(output)")
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError("Build and run failed: \(error.localizedDescription)")
        }
    }

    private func extractBuildErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter {
            $0.contains("error:") || $0.contains("BUILD FAILED")
        }

        if errorLines.isEmpty {
            return lines.suffix(20).joined(separator: "\n")
        }

        return errorLines.joined(separator: "\n")
    }

    private func extractAppPath(from buildSettings: String) -> String? {
        // Look for CODESIGNING_FOLDER_PATH or TARGET_BUILD_DIR + FULL_PRODUCT_NAME
        let lines = buildSettings.components(separatedBy: .newlines)

        // First try CODESIGNING_FOLDER_PATH which is the complete .app path
        for line in lines where line.contains("CODESIGNING_FOLDER_PATH") {
            if let range = line.range(of: "/") {
                let path = String(line[range.lowerBound...])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: ",", with: "")
                if path.hasSuffix(".app") {
                    return path
                }
            }
        }

        // Fallback: try TARGET_BUILD_DIR + FULL_PRODUCT_NAME
        var targetBuildDir: String?
        var fullProductName: String?

        for line in lines {
            if line.contains("TARGET_BUILD_DIR") && !line.contains("EFFECTIVE") {
                if let equalsRange = line.range(of: " = ") {
                    targetBuildDir = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
            if line.contains("FULL_PRODUCT_NAME") {
                if let equalsRange = line.range(of: " = ") {
                    fullProductName = String(line[equalsRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        if let dir = targetBuildDir, let name = fullProductName {
            return "\(dir)/\(name)"
        }

        return nil
    }
}
