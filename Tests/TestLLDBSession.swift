import Foundation
@testable import XCMCPCore

/// Runs `body` against a fresh LLDB session and awaits the teardown on every exit path.
///
/// A `defer` cannot await, so `defer { Task { await session.terminate() } }` returns before the
/// debugger dies. The test then finishes while `lldb` and its `lldb-rpc-server` child are still
/// running, and the stray pair wedges the next debug launch. Awaiting the teardown here closes that
/// window for both the success path and the throwing path.
///
/// - Parameters:
///   - commandTimeout: The per-command read window the session starts with.
///   - body: The work to run against the session.
/// - Throws: Whatever `body` throws, after the session is terminated.
func withLLDBSession(
    commandTimeout: TimeInterval,
    _ body: (LLDBSession) async throws -> Void,
) async throws {
    let session = try LLDBSession(pid: 0, commandTimeout: commandTimeout)

    do {
        try await body(session)
    } catch {
        await session.terminate()
        throw error
    }
    await session.terminate()
}
