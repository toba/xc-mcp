import MCP
import XCMCPCore
import Foundation

public struct SetSessionDefaultsTool: Sendable {
    private let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "set_session_defaults",
            description:
            "Set default project, scheme, simulator, or device for the session. These defaults will be used by build and run tools when not explicitly specified.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Xcode project (.xcodeproj). Mutually exclusive with workspace_path.",
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Xcode workspace (.xcworkspace). Mutually exclusive with project_path.",
                        ),
                    ]),
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a Swift package directory containing Package.swift.",
                        ),
                    ]),
                    "scheme": .object([
                        "type": .string("string"),
                        "description": .string("Name of the scheme to use for builds"),
                    ]),
                    "simulator_udid": .object([
                        "type": .string("string"),
                        "description": .string("UDID of the simulator to use"),
                    ]),
                    "device_udid": .object([
                        "type": .string("string"),
                        "description": .string("UDID of the physical device to use"),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string("Build configuration (Debug or Release)"),
                    ]),
                    "env": .object([
                        "type": .string("object"),
                        "additionalProperties": .object(["type": .string("string")]),
                        "description": .string(
                            "Custom environment variables applied to all build/test/run commands. Keys are merged with existing env (new keys add, existing keys update).",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let projectPath = arguments.getString("project_path")
        let workspacePath = arguments.getString("workspace_path")
        let packagePath = arguments.getString("package_path")
        let scheme = arguments.getString("scheme")
        let simulatorUDID = arguments.getString("simulator_udid")
        let deviceUDID = arguments.getString("device_udid")
        let configuration = arguments.getString("configuration")

        // Validate that project and workspace are not both set
        if projectPath != nil, workspacePath != nil {
            throw MCPError.invalidParams(
                "Cannot set both project_path and workspace_path. They are mutually exclusive.",
            )
        }

        // Parse env dict
        var env: [String: String]?
        if case let .object(envDict) = arguments["env"] {
            var parsed: [String: String] = [:]
            for (key, value) in envDict {
                if case let .string(str) = value {
                    parsed[key] = str
                }
            }
            if !parsed.isEmpty {
                env = parsed
            }
        }

        // Validate configuration if provided
        if let config = configuration {
            let validConfigs = ["Debug", "Release"]
            if !validConfigs.contains(config) {
                throw MCPError.invalidParams(
                    "Invalid configuration '\(config)'. Must be one of: \(validConfigs.joined(separator: ", "))",
                )
            }
        }

        await sessionManager.setDefaults(
            projectPath: projectPath,
            workspacePath: workspacePath,
            packagePath: packagePath,
            scheme: scheme,
            simulatorUDID: simulatorUDID,
            deviceUDID: deviceUDID,
            configuration: configuration,
            env: env,
        )

        let summary = await sessionManager.summary()
        return CallTool.Result(
            content: [
                .text("Session defaults updated.\n\n\(summary)"),
            ],
        )
    }
}
