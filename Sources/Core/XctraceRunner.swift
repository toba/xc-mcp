import Foundation
import Subprocess

/// Result of an xctrace command execution.
public typealias XctraceResult = ProcessResult

/// Wrapper for executing xctrace commands.
///
/// `XctraceRunner` provides a Swift interface for invoking Apple's Instruments
/// command-line tool (`xctrace`). It supports recording traces with templates,
/// listing available templates/instruments/devices, and exporting trace data.
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
    /// - Throws: An error if the process fails to launch.
    public func run(arguments: [String]) async throws -> XctraceResult {
        try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["xctrace"] + arguments),
        )
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
    /// - Returns: The running Process instance.
    /// - Throws: An error if the process fails to launch.
    public func record(
        template: String,
        outputPath: String,
        device: String?,
        timeLimit: String?,
        attachPID: String?,
        attachName: String?,
        allProcesses: Bool,
    ) throws -> Process {
        var args = ["record", "--template", template, "--output", outputPath]

        if let device {
            args += ["--device", device]
        }

        if let timeLimit {
            args += ["--time-limit", timeLimit]
        }

        if let attachPID {
            args += ["--attach", attachPID]
        }

        if let attachName {
            args += ["--attach", attachName]
        }

        if allProcesses {
            args += ["--all-processes"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctrace"] + args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        return process
    }

    /// Lists available templates, instruments, or devices.
    ///
    /// - Parameter kind: The type of listing: "templates", "instruments", or "devices".
    /// - Returns: The result containing the list output.
    /// - Throws: An error if the process fails to launch.
    public func list(kind: String) async throws -> XctraceResult {
        try await run(arguments: ["list", kind])
    }

    /// Exports trace data from a `.trace` file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the `.trace` file.
    ///   - xpath: Optional XPath query for specific data tables.
    ///   - toc: Whether to show the table of contents.
    /// - Returns: The result containing the exported XML data.
    /// - Throws: An error if the process fails to launch.
    public func export(
        inputPath: String,
        xpath: String?,
        toc: Bool,
    ) async throws -> XctraceResult {
        var args = ["export", "--input", inputPath]

        if let xpath {
            args += ["--xpath", xpath]
        } else if toc {
            args += ["--toc"]
        }

        return try await run(arguments: args)
    }
}
