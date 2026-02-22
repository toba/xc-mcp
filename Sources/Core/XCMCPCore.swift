import Foundation

// Re-export MCP for convenience
@_exported import MCP

/// XCMCPCore - Shared utilities for Xcode MCP servers.
///
/// This module provides common functionality used by all xc-mcp servers:
/// - **Runners**: Execute command-line tools (xcodebuild, simctl, devicectl, lldb, swift)
/// - **SessionManager**: Manages session state and defaults
/// - **PathUtility**: Secure path resolution within sandboxed directories
/// - **ErrorExtractor**: Extracts relevant error information from build output
///
/// ## Usage
///
/// Import this module in any focused server to access shared utilities:
///
/// ```swift
/// import XCMCPCore
///
/// let runner = XcodebuildRunner()
/// let result = try await runner.build(...)
/// ```
///
/// ## Module Organization
///
/// - `ProcessResult`: Unified result type for all command executions
/// - `SessionManager`: Actor managing project/scheme/device defaults
/// - `PathUtility`: Path resolution with base directory validation
/// - `XcodebuildRunner`: Xcode build tool wrapper
/// - `SimctlRunner`: Simulator control wrapper
/// - `DeviceCtlRunner`: Device control wrapper
/// - `LLDBRunner`: LLDB debugger wrapper
/// - `SwiftRunner`: Swift CLI wrapper
/// - `ErrorExtractor`: Build error extraction utilities
/// - `ArgumentExtraction`: MCP argument parsing helpers
/// - `MCPErrorConvertible`: Protocol for converting domain errors to MCPError
public enum XCMCPCore {}

/// Encodes an `Encodable` value to a pretty-printed, sorted JSON string.
public func encodePrettyJSON(_ value: some Encodable, fallback: String = "{}") throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(data: data, encoding: .utf8) ?? fallback
}
