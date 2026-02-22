import MCP
import Foundation

/// Errors that can occur during path resolution and validation.
public enum PathError: LocalizedError, MCPErrorConvertible {
    /// The resolved path is outside the allowed base directory.
    case pathOutsideBasePath(path: String, basePath: String)

    public var errorDescription: String? {
        switch self {
            case let .pathOutsideBasePath(path, basePath):
                return "Path '\(path)' is outside the allowed base path '\(basePath)'"
        }
    }

    public func toMCPError() -> MCPError {
        .invalidParams(errorDescription ?? "Invalid path")
    }
}

/// Utility for resolving and validating file paths within a sandboxed base directory.
///
/// `PathUtility` ensures all file operations are restricted to a specific base directory,
/// preventing path traversal attacks and unauthorized file access.
///
/// ## Overview
///
/// The utility handles both absolute and relative paths:
/// - **Relative paths** are resolved relative to the base path
/// - **Absolute paths** are validated to be within the base path
///
/// ## Example
///
/// ```swift
/// let utility = PathUtility(basePath: "/Users/dev/projects")
///
/// // Resolve a relative path
/// let path = try utility.resolvePath(from: "MyApp/Sources")
/// // Returns: /Users/dev/projects/MyApp/Sources
///
/// // Absolute paths within base are allowed
/// let absolute = try utility.resolvePath(from: "/Users/dev/projects/MyApp")
/// // Returns: /Users/dev/projects/MyApp
///
/// // Paths outside base throw an error
/// try utility.resolvePath(from: "../outside") // Throws PathError
/// ```
///
/// ## Disabling Sandboxing
///
/// When running as an MCP server without a known working directory, sandboxing can be
/// disabled to allow access to any path:
///
/// ```swift
/// let utility = PathUtility(basePath: "/tmp", sandboxEnabled: false)
/// // All paths are allowed, basePath is only used for resolving relative paths
/// ```
public struct PathUtility: Sendable {
    /// The root directory for all path operations.
    public let basePath: String

    /// Whether path sandboxing is enabled.
    ///
    /// When `true` (the default), all resolved paths must be within the base path.
    /// When `false`, paths outside the base path are allowed.
    public let sandboxEnabled: Bool

    /// Creates a new path utility with the specified base directory.
    ///
    /// - Parameters:
    ///   - basePath: The root directory that constrains all path operations.
    ///   - sandboxEnabled: Whether to enforce that paths stay within the base directory.
    ///     Defaults to `true`.
    public init(basePath: String, sandboxEnabled: Bool = true) {
        self.basePath = basePath
        self.sandboxEnabled = sandboxEnabled
    }

    /// Resolves a path relative to the base path and validates it's within bounds.
    ///
    /// - Parameter path: The path to resolve (absolute or relative).
    /// - Returns: The resolved absolute path as a string.
    /// - Throws: ``PathError/pathOutsideBasePath(path:basePath:)`` if the path is outside the base directory.
    public func resolvePath(from path: String) throws(PathError) -> String {
        let resolvedURL = try resolvePathURL(from: path)
        return resolvedURL.path
    }

    /// Resolves a path URL relative to the base path and validates it's within bounds.
    ///
    /// - Parameter path: The path to resolve (absolute or relative).
    /// - Returns: The resolved URL.
    /// - Throws: ``PathError/pathOutsideBasePath(path:basePath:)`` if sandboxing is enabled
    ///   and the path is outside the base directory.
    public func resolvePathURL(from path: String) throws(PathError) -> URL {
        let baseURL = URL(fileURLWithPath: basePath).standardized

        let resolvedURL: URL
        if path.hasPrefix("/") {
            // Absolute path - must validate it's within base path (if sandboxing is enabled)
            resolvedURL = URL(fileURLWithPath: path).standardized
        } else {
            // Relative path - resolve relative to base path
            resolvedURL = baseURL.appendingPathComponent(path).standardized
        }

        // Only validate when sandboxing is enabled
        if sandboxEnabled {
            let basePath = baseURL.path
            let resolvedPath = resolvedURL.path

            if !resolvedPath.hasPrefix(basePath) {
                throw PathError.pathOutsideBasePath(path: resolvedPath, basePath: basePath)
            }
        }

        return resolvedURL
    }

    /// Converts an absolute path to a relative path from the base path.
    ///
    /// - Parameter absolutePath: The absolute path to convert.
    /// - Returns: The relative path from the base path, or `nil` if the path is outside the base directory.
    public func makeRelativePath(from absolutePath: String) -> String? {
        let baseURL = URL(fileURLWithPath: basePath).standardized
        let absoluteURL = URL(fileURLWithPath: absolutePath).standardized

        // Check if the absolute path is within the base path
        guard absoluteURL.path.hasPrefix(baseURL.path) else {
            return nil
        }

        // Get the relative components
        let baseComponents = baseURL.pathComponents
        let absoluteComponents = absoluteURL.pathComponents

        // Find common prefix
        var commonPrefixLength = 0
        for i in 0 ..< min(baseComponents.count, absoluteComponents.count) {
            if baseComponents[i] == absoluteComponents[i] {
                commonPrefixLength += 1
            } else {
                break
            }
        }

        // Build relative path
        let upComponents = Array(repeating: "..", count: baseComponents.count - commonPrefixLength)
        let downComponents = Array(absoluteComponents[commonPrefixLength...])
        let relativeComponents = upComponents + downComponents

        if relativeComponents.isEmpty {
            return "."
        }

        return relativeComponents.joined(separator: "/")
    }

    // MARK: - Ancestor Directory Search

    /// Walks up from a starting directory looking for a directory containing a file or
    /// subdirectory matching the given predicate.
    ///
    /// - Parameters:
    ///   - predicate: A closure that receives directory contents and returns the matching
    ///     entry name, or `nil` if no match is found.
    ///   - startingFrom: The directory to start searching from.
    /// - Returns: The path to the directory containing the match, or `nil` if not found.
    public static func findAncestorDirectory(
        matching predicate: (String) -> Bool,
        startingFrom start: String,
    ) -> String? {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: start).standardized

        // Walk up at most 20 levels to avoid infinite loops on broken symlinks
        for _ in 0 ..< 20 {
            let dirPath = current.path
            if let entries = try? fm.contentsOfDirectory(atPath: dirPath),
               entries.contains(where: predicate)
            {
                return dirPath
            }
            let parent = current.deletingLastPathComponent().standardized
            if parent.path == current.path {
                break // Reached filesystem root
            }
            current = parent
        }
        return nil
    }

    /// Finds the nearest ancestor directory containing `Package.swift`,
    /// starting from the process's current working directory.
    ///
    /// - Returns: The Swift package root path, or `nil` if not found.
    public static func findPackageRoot() -> String? {
        findAncestorDirectory(
            matching: { $0 == "Package.swift" },
            startingFrom: FileManager.default.currentDirectoryPath,
        )
    }

    /// Finds the nearest ancestor directory containing a `.xcodeproj` bundle,
    /// starting from the process's current working directory.
    ///
    /// - Returns: The full path to the `.xcodeproj` bundle, or `nil` if not found.
    public static func findProjectPath() -> String? {
        guard
            let dir = findAncestorDirectory(
                matching: { $0.hasSuffix(".xcodeproj") },
                startingFrom: FileManager.default.currentDirectoryPath,
            )
        else { return nil }
        // Return the full .xcodeproj path, not just the containing directory
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard let proj = entries.first(where: { $0.hasSuffix(".xcodeproj") }) else { return nil }
        return "\(dir)/\(proj)"
    }

    /// Finds the nearest ancestor directory containing a `.xcworkspace` bundle,
    /// starting from the process's current working directory.
    ///
    /// - Returns: The full path to the `.xcworkspace` bundle, or `nil` if not found.
    public static func findWorkspacePath() -> String? {
        guard
            let dir = findAncestorDirectory(
                matching: {
                    $0.hasSuffix(".xcworkspace")
                        && !$0.hasPrefix(".")
                        && $0 != "Pods.xcworkspace"
                },
                startingFrom: FileManager.default.currentDirectoryPath,
            )
        else { return nil }
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        guard
            let ws = entries.first(where: {
                $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".") && $0 != "Pods.xcworkspace"
            })
        else { return nil }
        return "\(dir)/\(ws)"
    }

    /// Resolves a path URL without base path validation (legacy compatibility).
    ///
    /// - Parameter path: The path to resolve.
    /// - Returns: The resolved URL.
    /// - Note: This method does not validate paths against a base directory.
    ///   Prefer the instance method ``resolvePathURL(from:)`` for secure path handling.
    static func resolvePathURL(from path: String) -> URL {
        let url = URL(fileURLWithPath: path)

        if url.path.hasPrefix("/") {
            return url
        } else {
            let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            return currentDirectory.appendingPathComponent(path).standardized
        }
    }

    /// Resolves a path without base path validation (legacy compatibility).
    ///
    /// - Parameter path: The path to resolve.
    /// - Returns: The resolved absolute path as a string.
    /// - Note: This method does not validate paths against a base directory.
    ///   Prefer the instance method ``resolvePath(from:)`` for secure path handling.
    static func resolvePath(from path: String) -> String {
        resolvePathURL(from: path).path
    }
}
