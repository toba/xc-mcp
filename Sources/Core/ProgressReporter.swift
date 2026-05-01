import MCP
import Foundation
import Synchronization

/// Streams periodic last-line snapshots from a long-running process to an MCP
/// client via `notifications/progress`.
///
/// Use ``stream(_:)`` to wrap a body that drives a process whose stdout/stderr
/// chunks are fed in via ``ingest(_:)``. While the body runs, a background task
/// polls the latest line and emits a ``ProgressNotification`` no more often
/// than `interval`.
///
/// Errors from `notify` are swallowed — failed progress delivery must never
/// fail the underlying tool call.
public final class ProgressReporter: Sendable {
    private struct State {
        var totalBytes: Int = 0
        var lastLine: String = ""
        var lastSentLine: String = ""
        var retired: Bool = false
    }

    private let state = Mutex(State())
    private let token: ProgressToken
    private let interval: Duration
    private let notify: @Sendable (Message<ProgressNotification>) async throws -> Void

    public init(
        token: ProgressToken,
        interval: Duration = .seconds(2),
        notify: @escaping @Sendable (Message<ProgressNotification>) async throws -> Void,
    ) {
        self.token = token
        self.interval = interval
        self.notify = notify
    }

    /// Feeds a chunk of process output into the reporter.
    ///
    /// Cheap and lock-bounded — safe to call from a streaming hot path.
    public func ingest(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        state.withLock { s in
            s.totalBytes += chunk.utf8.count
            for line in chunk.split(whereSeparator: \.isNewline).reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    s.lastLine = trimmed
                    return
                }
            }
        }
    }

    /// Marks this reporter retired. After retirement, ``emitIfPending()`` drops
    /// any pending or in-flight notification rather than sending a stale
    /// progress message for a request the client no longer cares about.
    ///
    /// Sending a progress notification for a cancelled / unknown token causes
    /// the MCP client to treat it as a transport-level error and tear down the
    /// stdio pipe, which kills the entire server for the rest of the session.
    public func retire() {
        state.withLock { $0.retired = true }
    }

    /// Drains a single notification if a new line is available.
    ///
    /// Returns the parameters that would be (or were) sent. Visible for testing
    /// and used internally by the polling task in ``stream(_:)``.
    public func emitIfPending() async -> ProgressNotification.Parameters? {
        let snapshot = state.withLock { s -> ProgressNotification.Parameters? in
            guard !s.retired, !s.lastLine.isEmpty, s.lastLine != s.lastSentLine else { return nil }
            s.lastSentLine = s.lastLine
            return ProgressNotification.Parameters(
                progressToken: token,
                progress: Double(s.totalBytes),
                total: nil,
                message: String(s.lastLine.prefix(200)),
            )
        }
        guard let snapshot else { return nil }
        // Re-check just before sending to minimize the window between
        // snapshot and wire — if the request was cancelled while we were
        // preparing this notification, drop it.
        guard state.withLock({ !$0.retired }) else { return nil }
        try? await notify(ProgressNotification.message(snapshot))
        return snapshot
    }

    /// Runs `body` while a background task emits progress notifications.
    ///
    /// The reporter is retired synchronously when the surrounding task is
    /// cancelled (e.g. the client sent `notifications/cancelled`), so the
    /// poller stops emitting before the cancellation has finished propagating
    /// through the subprocess teardown. Without this guard, the unstructured
    /// poll task can fire one final progress notification for a request the
    /// client has already abandoned, which the SDK treats as a fatal stdio
    /// transport error.
    public func stream<T: Sendable>(
        _ body: @Sendable () async throws -> T,
    ) async rethrows -> T {
        try await withTaskCancellationHandler {
            let pollTask = Task { [interval, self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    if Task.isCancelled { break }
                    _ = await self.emitIfPending()
                }
            }
            defer {
                self.retire()
                pollTask.cancel()
            }
            return try await body()
        } onCancel: {
            self.retire()
        }
    }

    /// Convenience adapter for runners that take a `(String) -> Void` callback.
    public var onProgress: @Sendable (String) -> Void {
        { [self] chunk in self.ingest(chunk) }
    }
}
