import MCP
import Foundation

/// Resolves DerivedData project root paths from xcodebuild build settings.
///
/// Multiple diagnostic tools need the DerivedData project root (e.g. to find build logs, output
/// file maps, or serialized diagnostics). This utility centralizes that resolution.
public enum DerivedDataLocator {
    /// Finds the DerivedData project root by extracting `BUILD_DIR` from xcodebuild.
    ///
    /// `BUILD_DIR` is typically `…/DerivedData/ProjectName-hash/Build/Products`. This method strips
    /// the trailing `Build/Products` to return the project root.
    ///
    /// - Parameters:
    ///   - xcodebuildRunner: The runner to invoke xcodebuild.
    ///   - projectPath: Path to the .xcodeproj file.
    ///   - workspacePath: Path to the .xcworkspace file.
    ///   - scheme: The scheme to query.
    ///   - configuration: Build configuration. Defaults to "Debug".
    ///   - destination: The build destination whose platform-scoped DerivedData to resolve.
    ///     Defaults to `platform=macOS` (every current caller is a macOS build diagnostic). Must
    ///     match the destination the artifacts were built with, since DerivedData is namespaced per
    ///     platform.
    /// - Returns: The DerivedData project root path.
    /// - Throws: ``MCPError/internalError(_:)`` if BUILD_DIR cannot be determined.
    public static func findProjectRoot(
        xcodebuildRunner: XcodebuildRunner,
        projectPath: String?,
        workspacePath: String?,
        scheme: String,
        configuration: String = "Debug",
        destination: String = XcodebuildRunner.macOSDestination,
    ) async throws -> String {
        let result = try await xcodebuildRunner.showBuildSettings(
            projectPath: projectPath,
            workspacePath: workspacePath,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
        )

        guard let buildDir = BuildSettingExtractor.extractSetting("BUILD_DIR", from: result.stdout)
        else {
            throw MCPError.internalError("Could not determine DerivedData path from build settings")
        }

        // BUILD_DIR = .../DerivedData/Project-hash/Build/Products Go up two levels to the project
        // root
        let url = URL(fileURLWithPath: buildDir)
            .deletingLastPathComponent()  // Products
            .deletingLastPathComponent()  // Build
        return url.path
    }

    /// Finds the Intermediates.noindex directory within a DerivedData project root.
    ///
    /// - Parameter projectRoot: The DerivedData project root.
    /// - Returns: Path to `Build/Intermediates.noindex`.
    public static func intermediatesPath(projectRoot: String) -> String {
        URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("Build/Intermediates.noindex")
            .path
    }
}
