import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Utility for reading and writing Info.plist files associated with Xcode project targets.
public enum InfoPlistUtility {
    /// A project loaded from disk that carries the requested target
    public struct LoadedProject {
        public let xcodeproj: XcodeProj
        public let projectURL: URL

        /// The directory a relative `INFOPLIST_FILE` resolves against.
        public var projectDir: String { projectURL.deletingLastPathComponent().path }
    }

    /// The outcome of locating a target's Info.plist for reading
    public enum ReadOutcome {
        case plist([String: AnyValue])
        /// The text the tool returns when there is nothing to read.
        case message(String)
    }

    /// Loads a project and confirms it holds the named target.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file, absolute or relative.
    ///   - targetName: The target the caller named.
    ///   - pathUtility: Resolves `projectPath` against the session base path.
    /// - Returns: The loaded project, or `nil` when no target carries that name.
    /// - Throws: `MCPError` when the path does not resolve or the project does not load.
    public static func loadProject(
        projectPath: String,
        targetName: String,
        pathUtility: PathUtility,
    ) throws -> LoadedProject? {
        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
        let projectURL = URL(fileURLWithPath: resolvedProjectPath)
        let xcodeproj = try XcodeProj(path: Path(projectURL.path))

        guard xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) else {
            return nil
        }

        return LoadedProject(xcodeproj: xcodeproj, projectURL: projectURL)
    }

    /// Reads a target's Info.plist, creating nothing.
    ///
    /// A target that generates its Info.plist has no file to read, so the caller gets a message to
    /// return rather than an error. The write path calls
    /// ``materializeInfoPlist(xcodeproj:projectDir:targetName:projectPath:)`` instead.
    ///
    /// - Parameters:
    ///   - projectPath: Path to the .xcodeproj file, absolute or relative.
    ///   - targetName: The target whose plist to read.
    ///   - pathUtility: Resolves `projectPath` against the session base path.
    /// - Returns: The plist contents, or the text to return when there is no plist to read.
    /// - Throws: `MCPError` when the project does not load or the plist does not parse.
    public static func readInfoPlist(
        projectPath: String,
        targetName: String,
        pathUtility: PathUtility,
    ) throws -> ReadOutcome {
        guard let loaded = try loadProject(
            projectPath: projectPath, targetName: targetName, pathUtility: pathUtility,
        ) else {
            return .message("Target '\(targetName)' not found in project")
        }

        guard let plistPath = resolveInfoPlistPath(
            xcodeproj: loaded.xcodeproj, projectDir: loaded.projectDir, targetName: targetName,
        ) else {
            return .message(
                "No Info.plist found for target '\(targetName)'. The target may use a generated Info.plist with no physical file."
            )
        }

        return try .plist(readInfoPlist(path: plistPath))
    }

    /// Resolves the path to a target's Info.plist file from its `INFOPLIST_FILE` build setting.
    ///
    /// Checks the Debug configuration first, then falls back to the first available configuration.
    ///
    /// - Parameters:
    ///   - xcodeproj: The loaded Xcode project.
    ///   - projectDir: The directory containing the .xcodeproj bundle.
    ///   - targetName: The name of the target to find the plist for.
    /// - Returns: The absolute path to the Info.plist, or `nil` if not set or not found on disk.
    public static func resolveInfoPlistPath(
        xcodeproj: XcodeProj,
        projectDir: String,
        targetName: String,
    ) -> String? {
        guard let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
        else { return nil }

        // Try Debug config first, then any config
        let configs = target.buildConfigurationList?.buildConfigurations ?? []
        let debugConfig = configs.first { $0.name == "Debug" }
        let configToCheck = debugConfig ?? configs.first

        guard let plistFile = configToCheck?.buildSettings["INFOPLIST_FILE"]?.stringValue,
              !plistFile.isEmpty else { return nil }

        // Resolve relative to project directory
        let resolvedPath: String
        resolvedPath = plistFile.hasPrefix("/")
            ? plistFile
            : URL(fileURLWithPath: projectDir).appendingPathComponent(plistFile).standardized.path

        guard FileManager.default.fileExists(atPath: resolvedPath) else { return nil }

        return resolvedPath
    }

    /// Reads an Info.plist file and returns its contents as a dictionary.
    ///
    /// Every value keeps the type the file gave it, so a write of the result returns the file
    /// unchanged apart from the keys the caller edited.
    ///
    /// - Parameter path: The absolute path to the Info.plist file.
    /// - Returns: The plist contents as a string-keyed dictionary.
    /// - Throws: `MCPError` if the file cannot be read or parsed.
    public static func readInfoPlist(path: String) throws -> [String: AnyValue] {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw MCPError.internalError("Failed to read Info.plist at \(path)")
        }

        do {
            return try PropertyListDecoder().decode([String: AnyValue].self, from: data)
        } catch {
            throw MCPError.internalError("Info.plist at \(path) is not a dictionary")
        }
    }

    /// Writes a dictionary back to an Info.plist file in XML format.
    ///
    /// - Parameters:
    ///   - plist: The dictionary to write.
    ///   - path: The absolute path to write the Info.plist file.
    /// - Throws: `MCPError` if serialization or writing fails.
    public static func writeInfoPlist(_ plist: [String: AnyValue], toPath path: String) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(plist).write(to: URL(fileURLWithPath: path))
    }

    /// Creates an Info.plist file for targets that use `GENERATE_INFOPLIST_FILE` without a physical
    /// file.
    ///
    /// Creates `{targetName}/Info.plist` relative to the project directory, sets `INFOPLIST_FILE`
    /// on all build configurations (keeping `GENERATE_INFOPLIST_FILE=YES` so Xcode merges both),
    /// and saves the project file.
    ///
    /// - Parameters:
    ///   - xcodeproj: The loaded Xcode project.
    ///   - projectDir: The directory containing the .xcodeproj bundle.
    ///   - targetName: The name of the target to materialize a plist for.
    ///   - projectPath: The path to the .xcodeproj for saving.
    /// - Returns: The absolute path to the newly created Info.plist.
    /// - Throws: `MCPError` if the target is not found or file operations fail.
    public static func materializeInfoPlist(
        xcodeproj: XcodeProj,
        projectDir: String,
        targetName: String,
        projectPath: Path,
    ) throws -> String {
        guard let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
        else {
            throw MCPError.invalidParams("Target '\(targetName)' not found")
        }

        // Create the Info.plist file
        let plistRelativePath = "\(targetName)/Info.plist"
        let plistAbsolutePath = URL(fileURLWithPath: projectDir).appendingPathComponent(
            plistRelativePath
        ).standardized
            .path

        // Create directory if needed
        let plistDir = URL(fileURLWithPath: plistAbsolutePath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: plistDir, withIntermediateDirectories: true)

        // Write an empty plist
        let emptyPlist: [String: AnyValue] = [:]
        try writeInfoPlist(emptyPlist, toPath: plistAbsolutePath)

        // Set INFOPLIST_FILE on all configurations
        let configs = target.buildConfigurationList?.buildConfigurations ?? []
        for config in configs {
            config.buildSettings["INFOPLIST_FILE"] = .string(plistRelativePath)
        }

        // Save the project
        try PBXProjWriter.write(xcodeproj, to: projectPath)

        return plistAbsolutePath
    }
}
