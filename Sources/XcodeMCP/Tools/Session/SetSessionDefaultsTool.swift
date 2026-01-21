import Foundation
import MCP

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
                            "Path to the Xcode project (.xcodeproj). Mutually exclusive with workspace_path."
                        ),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Xcode workspace (.xcworkspace). Mutually exclusive with project_path."
                        ),
                    ]),
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to a Swift package directory containing Package.swift."),
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
                ]),
                "required": .array([]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let projectPath: String?
        if case let .string(value) = arguments["project_path"] {
            projectPath = value
        } else {
            projectPath = nil
        }

        let workspacePath: String?
        if case let .string(value) = arguments["workspace_path"] {
            workspacePath = value
        } else {
            workspacePath = nil
        }

        let packagePath: String?
        if case let .string(value) = arguments["package_path"] {
            packagePath = value
        } else {
            packagePath = nil
        }

        let scheme: String?
        if case let .string(value) = arguments["scheme"] {
            scheme = value
        } else {
            scheme = nil
        }

        let simulatorUDID: String?
        if case let .string(value) = arguments["simulator_udid"] {
            simulatorUDID = value
        } else {
            simulatorUDID = nil
        }

        let deviceUDID: String?
        if case let .string(value) = arguments["device_udid"] {
            deviceUDID = value
        } else {
            deviceUDID = nil
        }

        let configuration: String?
        if case let .string(value) = arguments["configuration"] {
            configuration = value
        } else {
            configuration = nil
        }

        // Validate that project and workspace are not both set
        if projectPath != nil && workspacePath != nil {
            throw MCPError.invalidParams(
                "Cannot set both project_path and workspace_path. They are mutually exclusive.")
        }

        // Validate configuration if provided
        if let config = configuration {
            let validConfigs = ["Debug", "Release"]
            if !validConfigs.contains(config) {
                throw MCPError.invalidParams(
                    "Invalid configuration '\(config)'. Must be one of: \(validConfigs.joined(separator: ", "))"
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
            configuration: configuration
        )

        let summary = await sessionManager.summary()
        return CallTool.Result(
            content: [
                .text("Session defaults updated.\n\n\(summary)")
            ]
        )
    }
}
