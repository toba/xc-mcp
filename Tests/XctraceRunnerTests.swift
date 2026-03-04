import Testing
@testable import XCMCPCore

struct XctraceRunnerTests {
    @Test
    func `Runner initializes successfully`() {
        let runner = XctraceRunner()
        _ = runner // Verify it compiles and initializes
    }

    @Test
    func `List templates returns output`() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "templates")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test
    func `List instruments returns output`() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "instruments")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test
    func `List devices returns output`() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "devices")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test
    func `Export with invalid path fails gracefully`() async throws {
        let runner = XctraceRunner()
        let result = try await runner.export(
            inputPath: "/nonexistent/path.trace",
            xpath: nil,
            toc: true,
        )

        #expect(!result.succeeded)
    }

    @Test
    func `Run with invalid arguments fails gracefully`() async throws {
        let runner = XctraceRunner()
        let result = try await runner.run(arguments: ["invalid-command-that-does-not-exist"])

        #expect(!result.succeeded)
    }
}
