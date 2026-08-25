import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Covers the cancellation chokepoint and the subprocess output collectors.
///
/// Each test here holds a fix in place that the compiler cannot check. A response sent for a
/// cancelled request tears down the client pipe, and a truncated capture that reports no truncation
/// misleads every caller downstream.
@Suite struct CancellationAndOutputCaptureTests {
    // MARK: - asMCPError

    @Test
    func `asMCPError rethrows CancellationError rather than converting it`() {
        #expect(throws: CancellationError.self) { throw try CancellationError().asMCPError() }
    }

    @Test
    func `asMCPError returns an existing MCPError unchanged`() throws {
        let converted = try MCPError.invalidParams("bad input").asMCPError()
        guard case let .invalidParams(message) = converted else {
            Issue.record("expected invalidParams, got \(converted)")
            return
        }
        #expect(message == "bad input")
    }

    @Test
    func `asMCPError routes a convertible error through toMCPError`() throws {
        let converted = try ProcessError.timeout(duration: .seconds(3)).asMCPError()
        guard case let .internalError(message) = converted else {
            Issue.record("expected internalError, got \(converted)")
            return
        }
        #expect(message?.contains("timed out") == true)
    }

    @Test
    func `A cancelled task propagates CancellationError through a catch-all that uses asMCPError`()
        async
    {
        // The shape every tool execute now uses. A catch-all that rewraps instead would turn this
        // into an MCPError, and the server would answer a request the client abandoned.
        func toolBody() async throws -> String {
            do {
                try Task.checkCancellation()
                return "ran"
            } catch {
                throw try error.asMCPError()
            }
        }

        let task = Task {
            try await Task.sleep(for: .seconds(60))
            return try await toolBody()
        }
        task.cancel()

        let result = await task.result
        guard case let .failure(error) = result else {
            Issue.record("expected the cancelled task to fail")
            return
        }
        #expect(error is CancellationError)
    }

    // MARK: - Process.waitForExit

    @Test
    func `waitForExit returns for a process that exited before the wait began`() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        #expect(!process.isRunning)

        // A bare terminationHandler never fires here, because the process is already gone. The
        // isRunning re-check inside waitForExit is what keeps this from hanging.
        await process.waitForExit()
        #expect(process.terminationStatus == 0)
    }

    @Test
    func `waitForExit returns once a still-running process exits`() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.2"]
        try process.run()

        await process.waitForExit()
        #expect(!process.isRunning)
        #expect(process.terminationStatus == 0)
    }

    // MARK: - Cancellation releases a launched process

    @Test
    func `A defer terminates a launched process when the enclosing sleep is cancelled`()
        async throws
    {
        // The shape LaunchAppLogsSimTool and PreviewCaptureTool now use. Without the defer, a
        // cancel during the sleep skips the terminate and the child outlives the server. A
        // simulator is not needed to hold that shape in place.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]

        let task = Task {
            try process.run()
            defer { if process.isRunning { process.terminate() } }
            try await Task.sleep(for: .seconds(60))
            process.terminate()
        }

        // Let the child reach a running state before cancelling.
        try await Task.sleep(for: .milliseconds(200))
        #expect(process.isRunning)
        task.cancel()
        _ = await task.result

        await process.waitForExit()
        #expect(!process.isRunning)
    }

    // MARK: - Output capture truncation

    /// Emits exactly `byteCount` bytes on stdout, captured with a cap of `limit` bytes.
    private func capture(limit: Int, byteCount: Int) async throws -> ProcessResult {
        try await ProcessResult.runSubprocess(
            .path("/bin/sh"),
            arguments: ["-c", "head -c \(byteCount) /dev/zero | tr '\\0' 'a'"],
            outputLimit: limit,
        )
    }

    @Test
    func `Output under the cap is kept whole and reports no truncation`() async throws {
        let result = try await capture(limit: 4096, byteCount: 1000)
        #expect(result.stdout.utf8.count == 1000)
        #expect(!result.stdout.hasSuffix("[output truncated]"))
    }

    @Test
    func `Output between the cap and twice the cap is trimmed to the cap and reports truncation`()
        async throws
    {
        // This range only loses bytes in the final trim after the loop. An earlier version of the
        // fix recorded truncation inside the loop alone, so this range silently dropped data.
        let limit = 2048
        let result = try await capture(limit: limit, byteCount: 3000)
        #expect(result.stdout.utf8.count <= limit + 64)
        #expect(result.output.contains("truncated"))
    }

    @Test
    func `Output far past the cap is trimmed to the cap and reports truncation`() async throws {
        let limit = 2048
        let result = try await capture(limit: limit, byteCount: 200_000)
        #expect(result.stdout.utf8.count <= limit + 64)
        #expect(result.output.contains("truncated"))
    }

    @Test
    func `Truncation keeps the tail, because build errors land at the end`() async throws {
        let limit = 512
        let result = try await ProcessResult.runSubprocess(
            .path("/bin/sh"),
            arguments: ["-c", "head -c 5000 /dev/zero | tr '\\0' 'a'; printf 'FINAL_MARKER'"],
            outputLimit: limit,
        )
        #expect(result.stdout.contains("FINAL_MARKER"))
    }
}
