import Foundation
import MCP
import PathKit
import XcodeProj

/// Utility for reading and writing Info.plist files associated with Xcode project targets.
public enum InfoPlistUtility {
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
    guard
      let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
    else {
      return nil
    }

    // Try Debug config first, then any config
    let configs = target.buildConfigurationList?.buildConfigurations ?? []
    let debugConfig = configs.first { $0.name == "Debug" }
    let configToCheck = debugConfig ?? configs.first

    guard let plistFile = configToCheck?.buildSettings["INFOPLIST_FILE"]?.stringValue,
      !plistFile.isEmpty
    else {
      return nil
    }

    // Resolve relative to project directory
    let resolvedPath: String
    if plistFile.hasPrefix("/") {
      resolvedPath = plistFile
    } else {
      resolvedPath =
        URL(fileURLWithPath: projectDir).appendingPathComponent(plistFile).standardized.path
    }

    guard FileManager.default.fileExists(atPath: resolvedPath) else {
      return nil
    }

    return resolvedPath
  }

  /// Reads an Info.plist file and returns its contents as a dictionary.
  ///
  /// - Parameter path: The absolute path to the Info.plist file.
  /// - Returns: The plist contents as a string-keyed dictionary.
  /// - Throws: `MCPError` if the file cannot be read or parsed.
  public static func readInfoPlist(path: String) throws -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path) else {
      throw MCPError.internalError("Failed to read Info.plist at \(path)")
    }

    guard
      let plist = try PropertyListSerialization.propertyList(
        from: data, options: .mutableContainersAndLeaves, format: nil,
      ) as? [String: Any]
    else {
      throw MCPError.internalError("Info.plist at \(path) is not a dictionary")
    }

    return plist
  }

  /// Writes a dictionary back to an Info.plist file in XML format.
  ///
  /// - Parameters:
  ///   - plist: The dictionary to write.
  ///   - path: The absolute path to write the Info.plist file.
  /// - Throws: `MCPError` if serialization or writing fails.
  public static func writeInfoPlist(_ plist: [String: Any], toPath path: String) throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0,
    )
    try data.write(to: URL(fileURLWithPath: path))
  }

  /// Creates an Info.plist file for targets that use `GENERATE_INFOPLIST_FILE` without a physical file.
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
    guard
      let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
    else {
      throw MCPError.invalidParams("Target '\(targetName)' not found")
    }

    // Create the Info.plist file
    let plistRelativePath = "\(targetName)/Info.plist"
    let plistAbsolutePath =
      URL(fileURLWithPath: projectDir).appendingPathComponent(plistRelativePath).standardized
      .path

    // Create directory if needed
    let plistDir = URL(fileURLWithPath: plistAbsolutePath).deletingLastPathComponent().path
    try FileManager.default.createDirectory(
      atPath: plistDir, withIntermediateDirectories: true,
    )

    // Write an empty plist
    let emptyPlist: [String: Any] = [:]
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
