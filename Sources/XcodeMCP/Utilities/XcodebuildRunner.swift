import Foundation

/// Result of an xcodebuild command execution
public struct XcodebuildResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }

    public var output: String {
        if stderr.isEmpty {
            return stdout
        } else if stdout.isEmpty {
            return stderr
        } else {
            return stdout + "\n" + stderr
        }
    }
}

/// Wrapper for executing xcodebuild commands
public struct XcodebuildRunner: Sendable {
    public init() {}

    /// Execute an xcodebuild command with the given arguments
    public func run(arguments: [String]) async throws -> XcodebuildResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["xcodebuild"] + arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let result = XcodebuildResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Build a project for a specific destination
    public func build(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = []
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath = workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath = projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-destination", destination,
            "-configuration", configuration,
            "build",
        ]

        args += additionalArguments

        return try await run(arguments: args)
    }

    /// Build and run tests
    public func test(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        destination: String,
        configuration: String = "Debug",
        additionalArguments: [String] = []
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath = workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath = projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-destination", destination,
            "-configuration", configuration,
            "test",
        ]

        args += additionalArguments

        return try await run(arguments: args)
    }

    /// Clean the build
    public func clean(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        configuration: String = "Debug"
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath = workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath = projectPath {
            args += ["-project", projectPath]
        }

        args += ["-scheme", scheme, "-configuration", configuration, "clean"]

        return try await run(arguments: args)
    }

    /// List schemes in a project or workspace
    public func listSchemes(
        projectPath: String? = nil,
        workspacePath: String? = nil
    ) async throws -> XcodebuildResult {
        var args: [String] = ["-list", "-json"]

        if let workspacePath = workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath = projectPath {
            args += ["-project", projectPath]
        }

        return try await run(arguments: args)
    }

    /// Show build settings for a scheme
    public func showBuildSettings(
        projectPath: String? = nil,
        workspacePath: String? = nil,
        scheme: String,
        configuration: String = "Debug"
    ) async throws -> XcodebuildResult {
        var args: [String] = []

        if let workspacePath = workspacePath {
            args += ["-workspace", workspacePath]
        } else if let projectPath = projectPath {
            args += ["-project", projectPath]
        }

        args += [
            "-scheme", scheme,
            "-configuration", configuration,
            "-showBuildSettings",
            "-json",
        ]

        return try await run(arguments: args)
    }
}
