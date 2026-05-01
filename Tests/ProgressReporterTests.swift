import Testing
@testable import XCMCPCore
import Foundation
import MCP
import Synchronization

struct ProgressReporterTests {
    private final class Recorder: Sendable {
        private let messages = Mutex<[ProgressNotification.Parameters]>([])

        func record(_ message: Message<ProgressNotification>) async throws {
            messages.withLock { $0.append(message.params) }
        }

        var captured: [ProgressNotification.Parameters] {
            messages.withLock { $0 }
        }
    }

    @Test
    func `Emits last non-empty line as progress message`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("tok"), notify: recorder.record)

        reporter.ingest("Compiling Foo.swift\nCompiling Bar.swift\n\n")
        let emitted = await reporter.emitIfPending()

        #expect(emitted?.message == "Compiling Bar.swift")
        #expect((emitted?.progress ?? 0) > 0)
        #expect(recorder.captured.last?.message == "Compiling Bar.swift")
    }

    @Test
    func `Returns nil when last line has not changed`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .integer(42), notify: recorder.record)

        reporter.ingest("Compiling Foo.swift\n")
        _ = await reporter.emitIfPending()
        let second = await reporter.emitIfPending()

        #expect(second == nil)
        #expect(recorder.captured.count == 1)
    }

    @Test
    func `Returns nil when no output has been ingested`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("idle"), notify: recorder.record)

        let emitted = await reporter.emitIfPending()
        #expect(emitted == nil)
        #expect(recorder.captured.isEmpty)
    }

    @Test
    func `Tracks cumulative byte count across chunks`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("tok"), notify: recorder.record)

        reporter.ingest("first line\n")
        let first = await reporter.emitIfPending()
        reporter.ingest("second line\n")
        let second = await reporter.emitIfPending()

        #expect(first?.message == "first line")
        #expect(second?.message == "second line")
        #expect((second?.progress ?? 0) > (first?.progress ?? 0))
    }

    @Test
    func `Ignores empty and whitespace-only chunks`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("tok"), notify: recorder.record)

        reporter.ingest("")
        reporter.ingest("   \n\t\n")
        let emitted = await reporter.emitIfPending()
        // Whitespace-only chunks still bump byte count via ingest, but no
        // line is captured, so emitIfPending should still see no line.
        #expect(emitted == nil)
        #expect(recorder.captured.isEmpty)
    }

    @Test
    func `Truncates very long lines to 200 chars`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("tok"), notify: recorder.record)

        let longLine = String(repeating: "x", count: 500)
        reporter.ingest(longLine + "\n")
        let emitted = await reporter.emitIfPending()
        #expect(emitted?.message?.count == 200)
    }

    @Test
    func `Retired reporter drops pending emission`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(token: .string("tok"), notify: recorder.record)

        reporter.ingest("Compiling Foo.swift\n")
        reporter.retire()
        let emitted = await reporter.emitIfPending()

        #expect(emitted == nil)
        #expect(recorder.captured.isEmpty)
    }

    @Test
    func `Stream retires reporter when surrounding task is cancelled`() async {
        let recorder = Recorder()
        let reporter = ProgressReporter(
            token: .string("tok"),
            interval: .milliseconds(20),
            notify: recorder.record,
        )

        let task = Task {
            try? await reporter.stream {
                // Simulate a long-running process emitting a chunk every 10ms.
                for _ in 0..<200 {
                    reporter.ingest("Compiling line \(UUID().uuidString)\n")
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
        }

        // Let a few progress notifications flow, then cancel.
        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        await task.value

        let countAfterCancel = recorder.captured.count
        // Give the poller more than one interval to attempt another emission.
        try? await Task.sleep(for: .milliseconds(80))
        #expect(recorder.captured.count == countAfterCancel)
    }

    @Test
    func `Stream invokes body and supports nested ingest`() async throws {
        let recorder = Recorder()
        let reporter = ProgressReporter(
            token: .string("tok"),
            interval: .milliseconds(50),
            notify: recorder.record,
        )

        let result = try await reporter.stream {
            reporter.ingest("Compiling Foo.swift\n")
            return 42
        }
        #expect(result == 42)
    }

    @Test
    func `extraArgsFromEnvironment is empty when env var unset`() {
        unsetenv("XC_MCP_SWIFT_EXTRA_ARGS")
        #expect(SwiftRunner.extraArgsFromEnvironment().isEmpty)
    }

    @Test
    func `extraArgsFromEnvironment tokenizes whitespace-separated flags`() {
        setenv("XC_MCP_SWIFT_EXTRA_ARGS",
               "-Xswiftc -experimental-skip-non-inlinable-function-bodies", 1)
        defer { unsetenv("XC_MCP_SWIFT_EXTRA_ARGS") }
        #expect(
            SwiftRunner.extraArgsFromEnvironment() == [
                "-Xswiftc", "-experimental-skip-non-inlinable-function-bodies",
            ],
        )
    }

    @Test
    func `SwiftRunner streams stdout chunks to onProgress`() async throws {
        let chunks = Mutex<[String]>([])
        let runner = SwiftRunner()
        let result = try await runner.run(
            arguments: ["--version"],
            timeout: .seconds(30),
            onProgress: { chunk in
                chunks.withLock { $0.append(chunk) }
            },
        )
        #expect(result.succeeded)
        let captured = chunks.withLock { $0.joined() }
        #expect(captured.contains("Swift") || captured.contains("swift"))
    }
}
