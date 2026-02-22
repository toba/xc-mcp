import MCP
import Foundation

/// Holds all session defaults as a single value type.
///
/// Used for efficient batch retrieval of session state, reducing actor hops.
public struct SessionDefaults: Sendable {
    /// Path to the current Xcode project (.xcodeproj)
    public let projectPath: String?
    /// Path to the current Xcode workspace (.xcworkspace)
    public let workspacePath: String?
    /// Path to the current Swift package directory
    public let packagePath: String?
    /// Current scheme name
    public let scheme: String?
    /// Current simulator UDID
    public let simulatorUDID: String?
    /// Current physical device UDID
    public let deviceUDID: String?
    /// Current build configuration (Debug/Release)
    public let configuration: String?
}

/// Manages session state for the MCP server, including default project, scheme, and device settings
public actor SessionManager {
    /// Path to the current Xcode project (.xcodeproj)
    public private(set) var projectPath: String?

    /// Path to the current Xcode workspace (.xcworkspace)
    public private(set) var workspacePath: String?

    /// Path to the current Swift package directory
    public private(set) var packagePath: String?

    /// Current scheme name
    public private(set) var scheme: String?

    /// Current simulator UDID
    public private(set) var simulatorUDID: String?

    /// Current physical device UDID
    public private(set) var deviceUDID: String?

    /// Current build configuration (Debug/Release)
    public private(set) var configuration: String?

    public init() {}

    /// Set session defaults
    public func setDefaults(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        packagePath: String? = nil,
        scheme: String? = nil,
        simulatorUDID: String? = nil,
        deviceUDID: String? = nil,
        configuration: String? = nil,
    ) {
        if let projectPath {
            self.projectPath = projectPath
            // Clear workspace if project is set (mutually exclusive)
            if workspacePath == nil {
                self.workspacePath = nil
            }
        }
        if let workspacePath {
            self.workspacePath = workspacePath
            // Clear project if workspace is set (mutually exclusive)
            if projectPath == nil {
                self.projectPath = nil
            }
        }
        if let packagePath {
            self.packagePath = packagePath
        }
        if let scheme {
            self.scheme = scheme
        }
        if let simulatorUDID {
            self.simulatorUDID = simulatorUDID
        }
        if let deviceUDID {
            self.deviceUDID = deviceUDID
        }
        if let configuration {
            self.configuration = configuration
        }
    }

    /// Clear all session defaults
    public func clear() {
        projectPath = nil
        workspacePath = nil
        packagePath = nil
        scheme = nil
        simulatorUDID = nil
        deviceUDID = nil
        configuration = nil
    }

    /// Get the effective project or workspace path
    public var effectiveProjectPath: String? {
        workspacePath ?? projectPath
    }

    /// Check if a project or workspace is configured
    public var hasProject: Bool {
        projectPath != nil || workspacePath != nil
    }

    /// Get a summary of current session state
    public func summary() -> String {
        var lines: [String] = []

        if let workspacePath {
            lines.append("Workspace: \(workspacePath)")
        } else if let projectPath {
            lines.append("Project: \(projectPath)")
        } else {
            lines.append("Project: (not set)")
        }

        lines.append("Package: \(packagePath ?? "(not set)")")
        lines.append("Scheme: \(scheme ?? "(not set)")")
        lines.append("Configuration: \(configuration ?? "(not set)")")
        lines.append("Simulator: \(simulatorUDID ?? "(not set)")")
        lines.append("Device: \(deviceUDID ?? "(not set)")")

        return lines.joined(separator: "\n")
    }

    // MARK: - Batch Getter

    /// Gets all session defaults in a single actor hop.
    ///
    /// Use this method when you need multiple session values to avoid
    /// multiple actor context switches.
    ///
    /// - Returns: A ``SessionDefaults`` containing all current session values.
    public func getDefaults() -> SessionDefaults {
        SessionDefaults(
            projectPath: projectPath,
            workspacePath: workspacePath,
            packagePath: packagePath,
            scheme: scheme,
            simulatorUDID: simulatorUDID,
            deviceUDID: deviceUDID,
            configuration: configuration,
        )
    }

    // MARK: - Parameter Resolution

    /// Resolves the simulator UDID from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved simulator UDID.
    /// - Throws: MCPError.invalidParams if no simulator is available.
    public func resolveSimulator(from arguments: [String: Value]) throws(MCPError) -> String {
        if let value = arguments.getString("simulator") {
            return value
        }
        if let session = simulatorUDID {
            return session
        }
        throw MCPError.invalidParams(
            "simulator is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the device UDID from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved device UDID.
    /// - Throws: MCPError.invalidParams if no device is available.
    public func resolveDevice(from arguments: [String: Value]) throws(MCPError) -> String {
        if let value = arguments.getString("device") {
            return value
        }
        if let session = deviceUDID {
            return session
        }
        throw MCPError.invalidParams(
            "device is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the scheme from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved scheme name.
    /// - Throws: MCPError.invalidParams if no scheme is available.
    public func resolveScheme(from arguments: [String: Value]) throws(MCPError) -> String {
        if let value = arguments.getString("scheme") {
            return value
        }
        if let session = scheme {
            return session
        }
        throw MCPError.invalidParams(
            "scheme is required. Set it with set_session_defaults or pass it directly.",
        )
    }

    /// Resolves the build configuration from arguments or session defaults.
    ///
    /// - Parameters:
    ///   - arguments: The tool arguments dictionary.
    ///   - defaultValue: The fallback configuration if none is set. Defaults to "Debug".
    /// - Returns: The resolved configuration.
    public func resolveConfiguration(
        from arguments: [String: Value],
        default defaultValue: String = "Debug",
    ) -> String {
        arguments.getString("configuration") ?? configuration ?? defaultValue
    }

    /// Resolves project and workspace paths from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: A tuple containing the resolved project and workspace paths.
    /// - Throws: MCPError.invalidParams if neither project nor workspace is available.
    public func resolveBuildPaths(from arguments: [String: Value]) throws(MCPError) -> (
        project: String?, workspace: String?,
    ) {
        let project = arguments.getString("project_path") ?? projectPath
        let workspace = arguments.getString("workspace_path") ?? workspacePath
        if project == nil, workspace == nil {
            throw MCPError.invalidParams(
                "Either project_path or workspace_path is required. Set it with set_session_defaults or pass it directly.",
            )
        }
        return (project, workspace)
    }

    /// Resolves the package path from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: The resolved package path.
    /// - Throws: MCPError.invalidParams if no package path is available.
    public func resolvePackagePath(from arguments: [String: Value]) throws(MCPError) -> String {
        if let value = arguments.getString("package_path") {
            return value
        }
        if let session = packagePath {
            return session
        }
        throw MCPError.invalidParams(
            "package_path is required. Set it with set_session_defaults or pass it directly.",
        )
    }
}
