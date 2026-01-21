import Foundation

/// Result of a Swift command execution
public struct SwiftResult: Sendable {
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

/// Wrapper for executing Swift commands
public struct SwiftRunner: Sendable {
    public init() {}

    /// Execute a swift command with the given arguments
    public func run(arguments: [String], workingDirectory: String? = nil) async throws
        -> SwiftResult
    {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = arguments

            if let workingDirectory = workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            }

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

                let result = SwiftResult(
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

    /// Build a Swift package
    public func build(
        packagePath: String,
        configuration: String = "debug",
        product: String? = nil
    ) async throws -> SwiftResult {
        var args = ["build", "-c", configuration]
        if let product = product {
            args.append(contentsOf: ["--product", product])
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Run tests for a Swift package
    public func test(
        packagePath: String,
        filter: String? = nil
    ) async throws -> SwiftResult {
        var args = ["test"]
        if let filter = filter {
            args.append(contentsOf: ["--filter", filter])
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Run a Swift package executable
    public func runExecutable(
        packagePath: String,
        executableName: String? = nil,
        arguments: [String] = []
    ) async throws -> SwiftResult {
        var args = ["run"]
        if let executableName = executableName {
            args.append(executableName)
        }
        if !arguments.isEmpty {
            args.append("--")
            args.append(contentsOf: arguments)
        }
        return try await run(arguments: args, workingDirectory: packagePath)
    }

    /// Clean build artifacts
    public func clean(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "clean"], workingDirectory: packagePath)
    }

    /// Show package dependencies
    public func showDependencies(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "show-dependencies"], workingDirectory: packagePath)
    }

    /// Resolve package dependencies
    public func resolve(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "resolve"], workingDirectory: packagePath)
    }

    /// Update package dependencies
    public func update(packagePath: String) async throws -> SwiftResult {
        try await run(arguments: ["package", "update"], workingDirectory: packagePath)
    }
}
