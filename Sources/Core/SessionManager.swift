import MCP
import Foundation

/// Holds all session defaults as a single value type.
///
/// Used for efficient batch retrieval of session state, reducing actor hops.
public struct SessionDefaults: Sendable, Codable {
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

    /// Shared file path for persisting session defaults across server processes.
    /// Located in /tmp so it's cleared on reboot — no stale state across sessions.
    static let sharedFilePath = URL(fileURLWithPath: "/tmp/xc-mcp-session.json")

    /// Modification date of the shared file when we last loaded/saved it.
    /// Used to detect external changes from other server processes.
    private var lastKnownModDate: Date?

    public init() {
        if let defaults = Self.loadFromDisk() {
            projectPath = defaults.projectPath
            workspacePath = defaults.workspacePath
            packagePath = defaults.packagePath
            scheme = defaults.scheme
            simulatorUDID = defaults.simulatorUDID
            deviceUDID = defaults.deviceUDID
            configuration = defaults.configuration
        }
        lastKnownModDate = Self.fileModDate()
    }

    /// Loads session defaults from the shared file, if it exists.
    private static func loadFromDisk() -> SessionDefaults? {
        guard FileManager.default.fileExists(atPath: sharedFilePath.path) else { return nil }
        do {
            let data = try Data(contentsOf: sharedFilePath)
            return try JSONDecoder().decode(SessionDefaults.self, from: data)
        } catch {
            return nil
        }
    }

    /// Returns the modification date of the shared session file, or nil if it doesn't exist.
    private static func fileModDate() -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: sharedFilePath.path)[.modificationDate] as? Date
    }

    /// Reloads session defaults from disk if the shared file has been modified
    /// by another server process since we last loaded or saved.
    private func reloadIfNeeded() {
        let currentModDate = Self.fileModDate()
        guard currentModDate != lastKnownModDate else { return }
        if let defaults = Self.loadFromDisk() {
            projectPath = defaults.projectPath
            workspacePath = defaults.workspacePath
            packagePath = defaults.packagePath
            scheme = defaults.scheme
            simulatorUDID = defaults.simulatorUDID
            deviceUDID = defaults.deviceUDID
            configuration = defaults.configuration
        }
        lastKnownModDate = currentModDate
    }

    /// Persists current session defaults to the shared file.
    private func saveToDisk() {
        let defaults = getDefaults()
        do {
            let data = try JSONEncoder().encode(defaults)
            try data.write(to: Self.sharedFilePath, options: .atomic)
            lastKnownModDate = Self.fileModDate()
        } catch {
            // Best-effort — don't fail the operation if persistence fails
        }
    }

    /// Deletes the shared session file.
    private func deleteFromDisk() {
        try? FileManager.default.removeItem(at: Self.sharedFilePath)
    }

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
        saveToDisk()
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
        deleteFromDisk()
    }

    /// Get the effective project or workspace path
    public var effectiveProjectPath: String? {
        reloadIfNeeded()
        return workspacePath ?? projectPath
    }

    /// Check if a project or workspace is configured
    public var hasProject: Bool {
        reloadIfNeeded()
        return projectPath != nil || workspacePath != nil
    }

    /// Get a summary of current session state
    public func summary() -> String {
        reloadIfNeeded()
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
        reloadIfNeeded()
        return SessionDefaults(
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
        reloadIfNeeded()
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
        reloadIfNeeded()
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
        reloadIfNeeded()
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
        reloadIfNeeded()
        return arguments.getString("configuration") ?? configuration ?? defaultValue
    }

    /// Resolves project and workspace paths from arguments or session defaults.
    ///
    /// - Parameter arguments: The tool arguments dictionary.
    /// - Returns: A tuple containing the resolved project and workspace paths.
    /// - Throws: MCPError.invalidParams if neither project nor workspace is available.
    public func resolveBuildPaths(from arguments: [String: Value]) throws(MCPError) -> (
        project: String?, workspace: String?,
    ) {
        reloadIfNeeded()
        let project = arguments.getString("project_path") ?? projectPath
        let workspace = arguments.getString("workspace_path") ?? workspacePath
        if project == nil, workspace == nil {
            // Auto-detect by walking up from cwd; prefer workspace over project
            if let detectedWorkspace = PathUtility.findWorkspacePath() {
                return (nil, detectedWorkspace)
            }
            if let detectedProject = PathUtility.findProjectPath() {
                return (detectedProject, nil)
            }
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
        reloadIfNeeded()
        if let value = arguments.getString("package_path") {
            return value
        }
        if let session = packagePath {
            return session
        }
        // Auto-detect by walking up from cwd looking for Package.swift
        if let detected = PathUtility.findPackageRoot() {
            return detected
        }
        throw MCPError.invalidParams(
            "package_path is required. Set it with set_session_defaults or pass it directly.",
        )
    }
}
