import Foundation

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
        configuration: String? = nil
    ) {
        if let projectPath = projectPath {
            self.projectPath = projectPath
            // Clear workspace if project is set (mutually exclusive)
            if workspacePath == nil {
                self.workspacePath = nil
            }
        }
        if let workspacePath = workspacePath {
            self.workspacePath = workspacePath
            // Clear project if workspace is set (mutually exclusive)
            if projectPath == nil {
                self.projectPath = nil
            }
        }
        if let packagePath = packagePath {
            self.packagePath = packagePath
        }
        if let scheme = scheme {
            self.scheme = scheme
        }
        if let simulatorUDID = simulatorUDID {
            self.simulatorUDID = simulatorUDID
        }
        if let deviceUDID = deviceUDID {
            self.deviceUDID = deviceUDID
        }
        if let configuration = configuration {
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

        if let workspacePath = workspacePath {
            lines.append("Workspace: \(workspacePath)")
        } else if let projectPath = projectPath {
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
}
