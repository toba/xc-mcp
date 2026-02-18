import Testing

@testable import XCMCPCore

@Suite("XctraceRunner Tests")
struct XctraceRunnerTests {
    @Test("Runner initializes successfully")
    func testInit() {
        let runner = XctraceRunner()
        _ = runner  // Verify it compiles and initializes
    }

    @Test("List templates returns output")
    func testListTemplates() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "templates")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test("List instruments returns output")
    func testListInstruments() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "instruments")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test("List devices returns output")
    func testListDevices() async throws {
        let runner = XctraceRunner()
        let result = try await runner.list(kind: "devices")

        #expect(result.succeeded)
        #expect(!result.stdout.isEmpty || !result.stderr.isEmpty)
    }

    @Test("Export with invalid path fails gracefully")
    func testExportInvalidPath() async throws {
        let runner = XctraceRunner()
        let result = try await runner.export(
            inputPath: "/nonexistent/path.trace",
            xpath: nil,
            toc: true
        )

        #expect(!result.succeeded)
    }

    @Test("Run with invalid arguments fails gracefully")
    func testRunInvalidArgs() async throws {
        let runner = XctraceRunner()
        let result = try await runner.run(arguments: ["invalid-command-that-does-not-exist"])

        #expect(!result.succeeded)
    }
}
