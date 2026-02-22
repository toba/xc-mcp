import Foundation
import MCP
import Subprocess
import Synchronization

/// Wrapper for executing xcodebuild commands.
///
/// `XcodebuildRunner` provides a Swift interface for invoking Xcode's command-line
/// build tool. It supports building, testing, cleaning, and querying project information.
///
/// ## Example
///
/// ```swift
/// let runner = XcodebuildRunner()
///
/// // Build for simulator
/// let result = try await runner.build(
///     projectPath: "MyApp.xcodeproj",
///     scheme: "MyApp",
///     destination: "platform=iOS Simulator,name=iPhone 15",
///     configuration: "Debug"
/// )
///
/// if result.succeeded {
///     print("Build succeeded")
/// }
/// ```
public struct XcodebuildRunner: Sendable {
  /// Default timeout for build operations (5 minutes)
  public static let defaultTimeout: TimeInterval = 300

  /// Timeout for no-output detection (30 seconds without output = stuck)
  public static let outputTimeout: Duration = .seconds(30)

  /// Creates a new xcodebuild runner.
  public init() {}

  /// Executes an xcodebuild command with the given arguments.
  ///
  /// - Parameter arguments: The command-line arguments to pass to xcodebuild.
  /// - Returns: The result containing exit code and output.
  /// - Throws: An error if the process fails to launch.
  public func run(arguments: [String]) async throws -> XcodebuildResult {
    try await run(arguments: arguments, timeout: Self.defaultTimeout, onProgress: nil)
  }

  /// Executes an xcodebuild command with timeout and optional progress callback.
  ///
  /// - Parameters:
  ///   - arguments: The command-line arguments to pass to xcodebuild.
  ///   - timeout: Maximum time to wait for the build to complete.
  ///   - onProgress: Optional callback invoked with output lines as they arrive.
  /// - Returns: The result containing exit code and output.
  /// - Throws: An error if the process fails to launch or times out.
  public func run(
    arguments: [String],
    timeout: TimeInterval,
    onProgress: (@Sendable (String) -> Void)?,
  ) async throws -> XcodebuildResult {
    let outputCollector = OutputCollector()
    let lastOutputTime = LastOutputTime()
    let startTime = ContinuousClock.now
    let timeoutDuration = Duration.seconds(timeout)

    let executionResult = try await Subprocess.run(
      .name("xcrun"),
      arguments: Arguments(["xcodebuild"] + arguments),
    ) { (_: Execution, _, stdoutSeq: AsyncBufferSequence, stderrSeq: AsyncBufferSequence) in
      try await withThrowingTaskGroup(of: Void.self) { group in
        // Read stdout
        group.addTask {
          for try await chunk in stdoutSeq {
            chunk.withUnsafeBytes { bytes in
              let data = Data(bytes)
              outputCollector.appendStdout(data)
              lastOutputTime.update()
              if let text = String(data: data, encoding: .utf8) {
                onProgress?(text)
              }
            }
          }
        }

        // Read stderr
        group.addTask {
          for try await chunk in stderrSeq {
            chunk.withUnsafeBytes { bytes in
              let data = Data(bytes)
              outputCollector.appendStderr(data)
              lastOutputTime.update()
              if let text = String(data: data, encoding: .utf8) {
                onProgress?(text)
              }
            }
          }
        }

        // Watchdog: check timeout + stuck detection
        group.addTask {
          while true {
            try await Task.sleep(for: .milliseconds(100))

            let elapsed = startTime.duration(to: .now)
            if elapsed > timeoutDuration {
              let (stdout, stderr) = outputCollector.getOutput()
              throw XcodebuildError.timeout(
                duration: timeout,
                partialOutput: stdout + stderr,
              )
            }

            let timeSinceLastOutput = lastOutputTime.timeSinceLastOutput()
            if timeSinceLastOutput > Self.outputTimeout {
              let (stdout, stderr) = outputCollector.getOutput()
              let seconds =
                Double(timeSinceLastOutput.components.seconds)
                + Double(timeSinceLastOutput.components.attoseconds) / 1e18
              throw XcodebuildError.stuckProcess(
                noOutputFor: seconds,
                partialOutput: stdout + stderr,
              )
            }
          }
        }

        // Wait for stream readers to finish, then cancel watchdog
        var streamsDone = 0
        while try await group.next() != nil {
          streamsDone += 1
          if streamsDone >= 2 {
            group.cancelAll()
            break
          }
        }
      }
    }

    let (stdout, stderr) = outputCollector.getOutput()
    let exitCode: Int32 =
      switch executionResult.terminationStatus {
      case .exited(let code): code
      case .unhandledException(let code): code
      }

    return XcodebuildResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    )
  }

  /// Builds a project for a specific destination.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  ///   - scheme: The scheme to build.
  ///   - destination: The build destination (e.g., "platform=iOS Simulator,id=<UDID>").
  ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
  ///   - additionalArguments: Extra arguments to pass to xcodebuild.
  /// - Returns: The build result containing exit code and output.
  /// - Throws: An error if the process fails to launch.
  public func build(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    scheme: String,
    destination: String,
    configuration: String = "Debug",
    additionalArguments: [String] = [],
    timeout: TimeInterval = defaultTimeout,
    onProgress: (@Sendable (String) -> Void)? = nil,
  ) async throws -> XcodebuildResult {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += [
      "-scheme", scheme,
      "-destination", destination,
      "-configuration", configuration,
      "build",
    ]

    args += additionalArguments

    return try await run(arguments: args, timeout: timeout, onProgress: onProgress)
  }

  /// Builds a single target for a specific destination.
  ///
  /// Unlike ``build(projectPath:workspacePath:scheme:destination:configuration:additionalArguments:timeout:onProgress:)``
  /// which builds an entire scheme, this method uses `-target` to compile a single target.
  ///
  /// - Warning: The `-target` flag does not resolve Swift Package Manager dependencies or
  ///   cross-project references. On projects that use SPM packages, builds will fail with
  ///   cascading "missing module" errors. Prefer `-scheme` based builds for real projects.
  ///   This method is retained as a general-purpose runner primitive.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  ///   - target: The target to build.
  ///   - destination: The build destination (e.g., "platform=macOS").
  ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
  ///   - additionalArguments: Extra arguments to pass to xcodebuild.
  ///   - timeout: Maximum time to wait for the build to complete.
  ///   - onProgress: Optional callback invoked with output lines as they arrive.
  /// - Returns: The build result containing exit code and output.
  /// - Throws: An error if the process fails to launch.
  public func buildTarget(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    target: String,
    destination: String,
    configuration: String = "Debug",
    additionalArguments: [String] = [],
    timeout: TimeInterval = defaultTimeout,
    onProgress: (@Sendable (String) -> Void)? = nil,
  ) async throws -> XcodebuildResult {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += [
      "-target", target,
      "-destination", destination,
      "-configuration", configuration,
      "build",
    ]

    args += additionalArguments

    return try await run(arguments: args, timeout: timeout, onProgress: onProgress)
  }

  /// Builds and runs tests for a scheme.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  ///   - scheme: The scheme containing tests to run.
  ///   - destination: The test destination (e.g., "platform=iOS Simulator,id=<UDID>").
  ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
  ///   - onlyTesting: Test identifiers to run exclusively (e.g., "MyTests/testFoo").
  ///   - skipTesting: Test identifiers to skip.
  ///   - enableCodeCoverage: Whether to enable code coverage collection.
  ///   - resultBundlePath: Path to store the .xcresult bundle.
  ///   - additionalArguments: Extra arguments to pass to xcodebuild.
  /// - Returns: The test result containing exit code and output.
  /// - Throws: An error if the process fails to launch.
  public func test(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    scheme: String,
    destination: String,
    configuration: String = "Debug",
    onlyTesting: [String]? = nil,
    skipTesting: [String]? = nil,
    enableCodeCoverage: Bool = false,
    resultBundlePath: String? = nil,
    additionalArguments: [String] = [],
    timeout: TimeInterval = defaultTimeout,
  ) async throws -> XcodebuildResult {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += [
      "-scheme", scheme,
      "-destination", destination,
      "-configuration", configuration,
    ]

    // Add test selection arguments
    if let onlyTesting {
      for testIdentifier in onlyTesting {
        args += ["-only-testing:\(testIdentifier)"]
      }
    }

    if let skipTesting {
      for testIdentifier in skipTesting {
        args += ["-skip-testing:\(testIdentifier)"]
      }
    }

    // Add code coverage arguments
    if enableCodeCoverage {
      args += ["-enableCodeCoverage", "YES"]
    }

    if let resultBundlePath {
      args += ["-resultBundlePath", resultBundlePath]
    }

    args += ["test"]
    args += additionalArguments

    return try await run(arguments: args, timeout: timeout, onProgress: nil)
  }

  /// Cleans build artifacts for a scheme.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  ///   - scheme: The scheme to clean.
  ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
  /// - Returns: The clean result containing exit code and output.
  /// - Throws: An error if the process fails to launch.
  public func clean(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    scheme: String,
    configuration: String = "Debug",
  ) async throws -> XcodebuildResult {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += ["-scheme", scheme, "-configuration", configuration, "clean"]

    return try await run(arguments: args)
  }

  /// Lists all schemes in a project or workspace.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  /// - Returns: The result containing JSON-formatted scheme list.
  /// - Throws: An error if the process fails to launch.
  public func listSchemes(
    projectPath: String? = nil,
    workspacePath: String? = nil,
  ) async throws -> XcodebuildResult {
    var args: [String] = ["-list", "-json"]

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    return try await run(arguments: args)
  }

  /// Shows build settings for a scheme.
  ///
  /// - Parameters:
  ///   - projectPath: Path to the .xcodeproj file (mutually exclusive with workspacePath).
  ///   - workspacePath: Path to the .xcworkspace file (mutually exclusive with projectPath).
  ///   - scheme: The scheme to query.
  ///   - configuration: Build configuration (Debug or Release). Defaults to Debug.
  /// - Returns: The result containing JSON-formatted build settings.
  /// - Throws: An error if the process fails to launch.
  public func showBuildSettings(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    scheme: String,
    configuration: String = "Debug",
    destination: String? = nil,
  ) async throws -> XcodebuildResult {
    var args: [String] = []

    if let workspacePath {
      args += ["-workspace", workspacePath]
    } else if let projectPath {
      args += ["-project", projectPath]
    }

    args += [
      "-scheme", scheme,
      "-configuration", configuration,
    ]

    if let destination {
      args += ["-destination", destination]
    }

    args += [
      "-showBuildSettings",
      "-json",
    ]

    return try await run(arguments: args)
  }
}

// MARK: - Helper Types

/// Errors specific to xcodebuild execution.
public enum XcodebuildError: LocalizedError, Sendable, MCPErrorConvertible {
  /// The build exceeded the maximum allowed time.
  case timeout(duration: TimeInterval, partialOutput: String)

  /// The build process stopped producing output (likely stuck).
  case stuckProcess(noOutputFor: TimeInterval, partialOutput: String)

  public var errorDescription: String? {
    switch self {
    case .timeout(let duration, _):
      return "Build timed out after \(Int(duration)) seconds"
    case .stuckProcess(let noOutputFor, _):
      return "Build appears stuck (no output for \(Int(noOutputFor)) seconds)"
    }
  }

  /// The partial output captured before the error occurred.
  public var partialOutput: String {
    switch self {
    case .timeout(_, let output), .stuckProcess(_, let output):
      return output
    }
  }

  public func toMCPError() -> MCPError {
    let errors = ErrorExtractor.extractBuildErrors(from: partialOutput)
    let detail = errors.isEmpty ? partialOutput.suffix(2000) : errors[...]
    return MCPError.internalError("\(errorDescription ?? "Build error")\n\n\(detail)")
  }
}

/// Thread-safe output collector that appends Data synchronously from readabilityHandler
/// callbacks (which run on a serial dispatch queue), avoiding Task reordering issues.
private final class OutputCollector: Sendable {
  private let stdoutData = Mutex(Data())
  private let stderrData = Mutex(Data())

  func appendStdout(_ data: Data) {
    stdoutData.withLock { $0.append(data) }
  }

  func appendStderr(_ data: Data) {
    stderrData.withLock { $0.append(data) }
  }

  func getOutput() -> (stdout: String, stderr: String) {
    let out = stdoutData.withLock { String(data: $0, encoding: .utf8) ?? "" }
    let err = stderrData.withLock { String(data: $0, encoding: .utf8) ?? "" }
    return (out, err)
  }
}

/// Thread-safe tracker for the last time output was received.
private final class LastOutputTime: Sendable {
  private let lastTime = Mutex(ContinuousClock.now)

  func update() {
    lastTime.withLock { $0 = .now }
  }

  func timeSinceLastOutput() -> Duration {
    lastTime.withLock { $0.duration(to: .now) }
  }
}
