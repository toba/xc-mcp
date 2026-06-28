import Testing
import Foundation
@testable import XCMCPCore

@Suite(.serialized)
struct SessionManagerWarmupTests {
    private func makeTempPath() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xc-mcp-warmup-test-\(UUID().uuidString).json")
    }

    /// Polls `manager.warmupState(for:)` until the warmup reports `.completed` or `timeout`
    /// elapses. Returns `true` if completion was observed, `false` on timeout.
    ///
    /// The default is generous because the warmup task runs at `.background` priority and the
    /// poll uses `Task.sleep` on the Swift cooperative thread pool, both of which the full
    /// parallel test suite (1400+ tests) can starve with blocking calls in other suites —
    /// deferring the warmup's first tick well past its actual (sub-second) completion. A 15s
    /// budget still flaked on a saturated CI runner (warmup completed in 0.08s but wasn't
    /// observed until ~18s), so the budget is large enough that only a genuine hang trips it.
    @discardableResult
    private func waitUntilCompleted(
        manager: SessionManager,
        packagePath: String,
        timeout: Duration = .seconds(60),
    ) async throws -> Bool {
        let started = ContinuousClock.now

        while ContinuousClock.now - started < timeout {
            if case .completed = await manager.warmupState(for: packagePath) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// Creates a temporary cold-cache package directory with a minimal Package.swift.
    private func makeTempPackage() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xc-mcp-pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(name: "Tmp", targets: [.target(name: "Tmp")])
            """
        try Data(manifest.utf8).write(to: dir.appendingPathComponent("Package.swift"))
        return dir
    }

    @Test
    func `Warmup runs and reports completed for cold cache`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }
        let pkgDir = try makeTempPackage()
        defer { try? FileManager.default.removeItem(at: pkgDir) }

        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in
                try await Task.sleep(for: .milliseconds(50))
            },
        )
        await manager.setDefaults(packagePath: pkgDir.path)

        if try await !waitUntilCompleted(manager: manager, packagePath: pkgDir.path) {
            Issue.record(
                "Warmup did not complete within the poll budget; state=\(await String(describing: manager.warmupState(for: pkgDir.path)))"
            )
        }
    }

    @Test
    func `Warmup is skipped when XC_MCP_DISABLE_WARMUP is set via init flag`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }
        let pkgDir = try makeTempPackage()
        defer { try? FileManager.default.removeItem(at: pkgDir) }

        let runCount = AsyncCounter()
        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in await runCount.increment() },
            enableWarmup: false,
        )
        await manager.setDefaults(packagePath: pkgDir.path)
        try await Task.sleep(for: .milliseconds(100))

        #expect(await runCount.value == 0)
        #expect(await manager.warmupState(for: pkgDir.path) == nil)
    }

    @Test
    func `Repeat setDefaults does not spawn duplicate warmups`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }
        let pkgDir = try makeTempPackage()
        defer { try? FileManager.default.removeItem(at: pkgDir) }

        let runCount = AsyncCounter()
        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in
                try await Task.sleep(for: .milliseconds(200))
                await runCount.increment()
            },
        )
        await manager.setDefaults(packagePath: pkgDir.path)
        await manager.setDefaults(packagePath: pkgDir.path)
        await manager.setDefaults(packagePath: pkgDir.path)

        // Poll for the (single) warmup to complete. A fixed sleep here was flaky on CI: the warmup
        // task runs at .background priority, so under runner starvation it could be deferred long
        // enough that runCount was still 0 when the assertion fired. Use the generous default
        // budget (explicit 5s/15s overrides here both still flaked on saturated runners —
        // #264/#267).
        try await waitUntilCompleted(manager: manager, packagePath: pkgDir.path)
        // Brief grace period to surface any spurious duplicate warmups that would also increment
        // runCount.
        try await Task.sleep(for: .milliseconds(100))

        #expect(await runCount.value == 1)
    }

    @Test
    func `cancelWarmupIfRunning stops the in-flight task`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }
        let pkgDir = try makeTempPackage()
        defer { try? FileManager.default.removeItem(at: pkgDir) }

        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in
                // Long sleep that should be cancelled.
                try await Task.sleep(for: .seconds(30))
            },
        )
        await manager.setDefaults(packagePath: pkgDir.path)
        try await Task.sleep(for: .milliseconds(20))
        // Sanity: warmup is running.
        if case .running = await manager.warmupState(for: pkgDir.path) {
        } else {
            Issue.record("Expected running state before cancel")
        }

        await manager.cancelWarmupIfRunning(packagePath: pkgDir.path)

        if case .cancelled = await manager.warmupState(for: pkgDir.path) {
        } else {
            Issue.record(
                "Expected cancelled state after cancel; got \(await String(describing: manager.warmupState(for: pkgDir.path)))"
            )
        }
    }

    @Test
    func `cancelWarmupIfRunning is a no-op when no warmup is running`() async {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }

        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in },
            enableWarmup: false,
        )
        await manager.cancelWarmupIfRunning(packagePath: "/nonexistent/path")
        #expect(await manager.warmupState(for: "/nonexistent/path") == nil)
    }

    @Test
    func `Warmup is not triggered when Package.swift is missing`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }

        let runCount = AsyncCounter()
        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in await runCount.increment() },
        )
        await manager.setDefaults(
            packagePath: "/tmp/definitely-not-a-swift-package-\(UUID().uuidString)")
        try await Task.sleep(for: .milliseconds(50))

        #expect(await runCount.value == 0)
    }

    @Test
    func `Summary includes warmup state when set`() async throws {
        let sessionPath = makeTempPath()
        defer { try? FileManager.default.removeItem(at: sessionPath) }
        let pkgDir = try makeTempPackage()
        defer { try? FileManager.default.removeItem(at: pkgDir) }

        let manager = SessionManager(
            filePath: sessionPath,
            warmupRunner: { _ in
                try await Task.sleep(for: .milliseconds(20))
            },
        )
        await manager.setDefaults(packagePath: pkgDir.path)

        try await waitUntilCompleted(manager: manager, packagePath: pkgDir.path)

        let summary = await manager.summary()
        #expect(summary.contains("Warmup: warmed"))
    }
}

/// Simple actor-based counter for incrementing from inside Sendable closures.
private actor AsyncCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
