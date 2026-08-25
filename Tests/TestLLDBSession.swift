import Foundation
@testable import XCMCPCore

/// Runs `body` against a fresh LLDB session and awaits the teardown on every exit path.
///
/// The teardown must be awaited. A fire-and-forget `Task { await session.terminate() }` returns
/// before the debugger dies, so the test finishes while `lldb` and its `lldb-rpc-server` child are
/// still running, and the stray pair wedges the next debug launch.
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
    defer { await session.terminate() }
    try await body(session)
}
