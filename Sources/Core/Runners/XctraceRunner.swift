import MCP
import Foundation
import Subprocess

/// Result of an xctrace command execution.
public typealias XctraceResult = ProcessResult

/// Wrapper for executing xctrace commands.
///
/// `XctraceRunner` provides a Swift interface for invoking Apple's Instruments command-line tool
/// (`xctrace`). It supports recording traces with templates, listing available
/// templates/instruments/devices, and exporting trace data.
///
/// ## Example
///
/// ```swift
/// let runner = XctraceRunner()
///
/// // List available templates
/// let result = try await runner.list(kind: "templates")
///
/// // Start a trace recording
/// let process = try runner.record(template: "Time Profiler", outputPath: "/tmp/trace.trace")
/// ```
public struct XctraceRunner: Sendable {
    public init() {}

    /// Executes an xctrace command with the given arguments and waits for completion.
    ///
    /// - Parameter arguments: The command-line arguments to pass to xctrace.
    /// - Returns: The result containing exit code and output.
    /// - Throws: ``XctraceError/commandFailed(_:)`` if the process fails to launch.
    public func run(arguments: [String]) async throws(XctraceError) -> XctraceResult {
        do {
            return try await ProcessResult.xcrun("xctrace", arguments: arguments)
        } catch {
            throw .commandFailed("\(error)")
        }
    }

    /// Starts a long-running trace recording, returning the Process for lifecycle management.
    ///
    /// The caller is responsible for stopping the recording by sending SIGINT
    /// (`process.interrupt()`) and waiting for exit (`process.waitUntilExit()`).
    ///
    /// - Parameters:
    ///   - template: The Instruments template name (e.g., "Time Profiler").
    ///   - outputPath: Path for the output `.trace` file.
    ///   - device: Optional device name or UDID. Omit for local Mac.
    ///   - timeLimit: Optional auto-stop duration (e.g., "30s", "5m").
    ///   - attachPID: Optional PID to attach to.
    ///   - attachName: Optional process name to attach to.
    ///   - allProcesses: Whether to record system-wide.
    ///   - launchPath: Optional path to an app bundle to launch under xctrace.
    /// - Returns: The running Process instance.
    /// - Throws: ``XctraceError/launchFailed(_:)`` if the process fails to launch.
    public func record(
        template: String,
        outputPath: String,
        device: String?,
        timeLimit: String?,
        attachPID: String?,
        attachName: String?,
        allProcesses: Bool,
        launchPath: String? = nil,
    ) throws(XctraceError) -> Process {
        var args = ["record", "--template", template, "--output", outputPath]

        if let device { args += ["--device", device] }

        if let timeLimit { args += ["--time-limit", timeLimit] }

        if let launchPath {
            args += ["--launch", "--", launchPath]
        } else if let attachPID {
            args += ["--attach", attachPID]
        } else if let attachName { args += ["--attach", attachName] }

        if allProcesses { args += ["--all-processes"] }

        let process = Process.xcrun("xctrace", arguments: args)

        do {
            try process.run()
        } catch {
            throw .launchFailed("\(error)")
        }
        return process
    }

    /// Lists available templates, instruments, or devices.
    ///
    /// - Parameter kind: The type of listing: "templates", "instruments", or "devices".
    /// - Returns: The result containing the list output.
    /// - Throws: ``XctraceError/commandFailed(_:)`` if the process fails to launch.
    public func list(kind: String) async throws(XctraceError) -> XctraceResult {
        try await run(arguments: ["list", kind])
    }

    /// Exports trace data from a `.trace` file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the `.trace` file.
    ///   - xpath: Optional XPath query for specific data tables.
    ///   - toc: Whether to show the table of contents.
    /// - Returns: The result containing the exported XML data.
    /// - Throws: ``XctraceError/commandFailed(_:)`` if the process fails to launch.
    public func export(
        inputPath: String,
        xpath: String?,
        toc: Bool,
    ) async throws(XctraceError) -> XctraceResult {
        var args = ["export", "--input", inputPath]

        if let xpath { args += ["--xpath", xpath] } else if toc { args += ["--toc"] }

        return try await run(arguments: args)
    }
}

/// Errors from ``XctraceRunner``.
public enum XctraceError: LocalizedError, Sendable, MCPErrorConvertible {
    /// An xctrace command failed to launch or to run to completion.
    case commandFailed(String)

    /// A long-running recording process failed to launch.
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
            case let .commandFailed(message): "xctrace command failed: \(message)"
            case let .launchFailed(message): "xctrace recording failed to start: \(message)"
        }
    }

    public func toMCPError() -> MCPError {
        .internalError(errorDescription ?? "xctrace operation failed")
    }
}
