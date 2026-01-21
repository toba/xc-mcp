import Foundation
import MCP

/// Errors thrown by XCStrings operations
public enum XCStringsError: Swift.Error, LocalizedError, Sendable, MCPErrorConvertible {
    case fileNotFound(path: String)
    case fileAlreadyExists(path: String)
    case invalidFileFormat(path: String, reason: String)
    case keyNotFound(key: String)
    case keyAlreadyExists(key: String)
    case languageNotFound(language: String, key: String)
    case writeError(path: String, reason: String)
    case invalidJSON(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .fileAlreadyExists(path):
            return "File already exists: \(path)"
        case let .invalidFileFormat(path, reason):
            return "Invalid file format at '\(path)': \(reason)"
        case let .keyNotFound(key):
            return "Key not found: '\(key)'"
        case let .keyAlreadyExists(key):
            return "Key already exists: '\(key)'"
        case let .languageNotFound(language, key):
            return "Language '\(language)' not found for key '\(key)'"
        case let .writeError(path, reason):
            return "Failed to write file at '\(path)': \(reason)"
        case let .invalidJSON(reason):
            return "Invalid JSON: \(reason)"
        }
    }

    /// Convert to MCPError for tool responses
    public func toMCPError() -> MCPError {
        switch self {
        case .fileNotFound, .keyNotFound, .languageNotFound:
            return .invalidParams(errorDescription ?? "Not found")
        case .fileAlreadyExists, .keyAlreadyExists:
            return .invalidParams(errorDescription ?? "Already exists")
        case .invalidFileFormat, .invalidJSON:
            return .invalidParams(errorDescription ?? "Invalid format")
        case .writeError:
            return .internalError(errorDescription ?? "Write failed")
        }
    }
}
