import MCP
import Logging
import XCMCPCore
import Foundation
import XCMCPTools

/// MCP server for Xcode project file manipulation.
///
/// This focused server provides tools for creating and modifying .xcodeproj files using the
/// XcodeProj library. It is stateless and does not require session management.
///
/// ## Token Efficiency
///
/// This server exposes the tools `ToolRegistry` marks with `ServerSet.project`. Selecting a focused
/// server trims the tool surface a client pays for.
///
/// ## Tools
///
/// - Project creation: `create_xcodeproj`
/// - Target management: `add_target`, `remove_target`, `duplicate_target`, `list_targets`
/// - File management: `add_file`, `remove_file`, `move_file`, `list_files`
/// - Group management: `create_group`, `list_groups`, `add_synchronized_folder`,
///   `add_target_to_synchronized_folder`, `add_synchronized_folder_exception`,
///   `remove_synchronized_folder_exception`, `list_synchronized_folder_exceptions`
/// - Build settings: `get_build_settings`, `set_build_setting`, `list_build_configurations`
/// - Dependencies: `add_dependency`, `add_framework`, `add_build_phase`, `remove_run_script_phase`,
///   `remove_subproject`
/// - Copy files phases: `list_copy_files_phases`, `add_copy_files_phase`,
///   `add_to_copy_files_phase`, `remove_from_copy_files_phase`, `remove_copy_files_phase`
/// - Swift packages: `add_swift_package`, `update_swift_package`, `list_swift_packages`,
///   `resolve_packages`, `show_package_resolution`, `remove_swift_package`
/// - App extensions: `add_app_extension`, `remove_app_extension`
public struct ProjectMCPServer: Sendable {
    private let basePath: String
    private let sandboxEnabled: Bool
    private let logger: Logger

    /// Creates a new project MCP server instance.
    ///
    /// - Parameters:
    ///   - basePath: The root directory for file operations.
    ///   - sandboxEnabled: Whether to enforce that paths stay within the base directory. Defaults
    ///     to `true`.
    ///   - logger: Logger instance for diagnostic output.
    public init(basePath: String, sandboxEnabled: Bool = true, logger: Logger) {
        self.basePath = basePath
        self.sandboxEnabled = sandboxEnabled
        self.logger = logger
    }

    /// Starts the MCP server and begins processing requests.
    public func run() async throws {
        let server = Server(
            name: "xc-project",
            version: "1.0.0",
            capabilities: .init(tools: .init()),
        )

        await installRegistryToolHandlers(
            on: server, as: .project,
            deps: ToolDeps(basePath: basePath, sandboxEnabled: sandboxEnabled))

        // Use stdio transport
        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
