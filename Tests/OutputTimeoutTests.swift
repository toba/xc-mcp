import MCP
import Testing
@testable import XCMCPCore

/// Covers the shared `output_timeout` resolution used by every build and query tool, and the
/// package-resolution phase tracker that widens the silence budget. (1ec1)
struct OutputTimeoutTests {
    // MARK: - resolveOutputTimeout

    @Test func `applies the default when neither parameter is given`() {
        let arguments: [String: Value] = ["scheme": .string("App")]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == .seconds(30))
    }

    @Test func `honors an explicit output_timeout`() {
        let arguments: [String: Value] = ["output_timeout": .int(240)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == .seconds(240))
    }

    @Test func `treats zero as disabling the check`() {
        let arguments: [String: Value] = ["output_timeout": .int(0)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == nil)
    }

    @Test func `keeps zero disabled even when a timeout is also given`() {
        let arguments: [String: Value] = ["output_timeout": .int(0), "timeout": .int(900)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == nil)
    }

    @Test func `an explicit timeout alone disables the check`() {
        let arguments: [String: Value] = ["timeout": .int(900)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == nil)
    }

    @Test func `output_timeout wins over an explicit timeout`() {
        let arguments: [String: Value] = ["output_timeout": .int(60), "timeout": .int(900)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == .seconds(60))
    }

    @Test(arguments: [-1, -5, -900])
    func `treats a negative output_timeout as disabling the check`(_ seconds: Int) {
        // A negative budget would fire on the first watchdog tick and report a stuck build that
        // never stalled. (37f6)
        let arguments: [String: Value] = ["output_timeout": .int(seconds)]
        #expect(arguments.resolveOutputTimeout(default: .seconds(30)) == nil)
    }

    // MARK: - resolveTimeout

    @Test func `resolveTimeout applies the default when the caller omits timeout`() {
        let arguments: [String: Value] = ["scheme": .string("App")]
        #expect(arguments.resolveTimeout(default: 300) == 300)
        #expect(arguments.resolveTimeout(default: Duration.seconds(300)) == .seconds(300))
    }

    @Test func `resolveTimeout honors an explicit timeout`() {
        let arguments: [String: Value] = ["timeout": .int(900)]
        #expect(arguments.resolveTimeout(default: 300) == 900)
        #expect(arguments.resolveTimeout(default: Duration.seconds(300)) == .seconds(900))
    }

    @Test func `explicitTimeout keeps the caller's choice distinguishable from an omission`() {
        #expect(([:] as [String: Value]).explicitTimeout() == nil)
        #expect((["timeout": .int(45)] as [String: Value]).explicitTimeout() == .seconds(45))
    }

    // MARK: - Schema

    @Test func `the schema property names the default and the zero escape hatch`() {
        let property = [String: Value].outputTimeoutSchemaProperty(defaultSeconds: 120)
        guard case let .object(entry) = property["output_timeout"],
              case let .string(description) = entry["description"]
        else {
            Issue.record("output_timeout property is missing a description")
            return
        }
        #expect(description.contains("Defaults to 120"))
        #expect(description.contains("Set to 0 to disable"))
    }

    @Test func `the schema property appends the caller's note`() {
        let property = [String: Value].outputTimeoutSchemaProperty(
            defaultSeconds: 30, note: "Extra guidance.",
        )
        guard case let .object(entry) = property["output_timeout"],
              case let .string(description) = entry["description"]
        else {
            Issue.record("output_timeout property is missing a description")
            return
        }
        #expect(description.hasSuffix("Extra guidance."))
    }

    @Test func `the test schema still exposes output_timeout`() {
        #expect([String: Value].testSchemaProperties["output_timeout"] != nil)
    }

    @Test func `the schema text reports the runner's resolution budget`() {
        let property = [String: Value].outputTimeoutSchemaProperty(defaultSeconds: 30)
        guard case let .object(entry) = property["output_timeout"],
              case let .string(description) = entry["description"]
        else {
            Issue.record("output_timeout property is missing a description")
            return
        }
        let seconds = XcodebuildRunner.packageResolutionOutputTimeout.components.seconds
        #expect(description.contains("\(seconds) seconds"))
    }

    @Test func `the query schema property carries the unresolved-packages note`() {
        let property = [String: Value].queryOutputTimeoutSchemaProperty
        guard case let .object(entry) = property["output_timeout"],
              case let .string(description) = entry["description"]
        else {
            Issue.record("output_timeout property is missing a description")
            return
        }
        #expect(description.contains("unresolved packages prints nothing"))
    }

    // MARK: - PackageResolutionPhase

    @Test func `the phase starts active because resolution precedes the first line`() {
        #expect(PackageResolutionPhase().isActive)
    }

    @Test func `ordinary output leaves the phase`() {
        let phase = PackageResolutionPhase()
        phase.update(from: "CompileSwift normal arm64\n")
        #expect(!phase.isActive)
    }

    @Test func `a resolution marker re-enters the phase`() {
        let phase = PackageResolutionPhase()
        phase.update(from: "CompileSwift normal arm64\n")
        phase.update(from: "Resolve Package Graph\n")
        #expect(phase.isActive)
    }

    @Test(arguments: [
        "Resolve Package Graph",
        "Resolving package graph",
        "Fetching from https://github.com/groue/GRDB.swift",
        "Cloning https://github.com/groue/GRDB.swift",
        "Checking out 6.0.0 of package 'grdb.swift'",
        "Computing target dependency graph",
    ])
    func `each marker enters the phase`(_ line: String) {
        let phase = PackageResolutionPhase()
        phase.update(from: "CompileSwift normal arm64\n")
        phase.update(from: line + "\n")
        #expect(phase.isActive)
    }

    @Test func `an indented marker still counts`() {
        let phase = PackageResolutionPhase()
        phase.update(from: "CompileSwift normal arm64\n")
        phase.update(from: "    Fetching from https://github.com/groue/GRDB.swift\n")
        #expect(phase.isActive)
    }

    @Test func `the last line of a chunk decides the phase`() {
        let phase = PackageResolutionPhase()
        phase.update(from: "Resolve Package Graph\nResolved source packages:\n  GRDB: 6.0.0\n")
        #expect(!phase.isActive)
    }

    @Test func `a blank line does not change the phase`() {
        let phase = PackageResolutionPhase()
        phase.update(from: "Resolve Package Graph\n")
        phase.update(from: "\n\n")
        #expect(phase.isActive)
    }

    @Test func `the resolution budget exceeds the standard budget`() {
        #expect(XcodebuildRunner.packageResolutionOutputTimeout > XcodebuildRunner.outputTimeout)
        #expect(
            XcodebuildRunner.packageResolutionOutputTimeout > XcodebuildRunner.deviceOutputTimeout,
        )
    }
}
