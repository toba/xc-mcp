import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Tests for the `xcodebuild` crash report that replaces a bare `Build failed (N warnings)` when
/// `swift-frontend` dies. (dcd0c744)
struct FrontendCrashDiagnosisTests {
    /// An IRGen crash in the shape `xcodebuild` prints it.
    private static let crashOutput = """
        SwiftCompile normal arm64 /p/View.swift (in target 'App' from project 'App')
        Stack dump:
        0.\tProgram arguments: /usr/bin/swift-frontend -frontend -c /p/Other.swift \
        -primary-file /p/View.swift -module-name App -o /tmp/View.o
        1.\tApple Swift version 6.3
        2.\tCompiling with the current language version
        3.\tWhile evaluating request IRGenRequest(IR Generation for file "/p/View.swift")
        4.\tWhile emitting IR SIL function "@$s4main1fyyF".
         for 'f()' (at /p/View.swift:12:5)
        error: Abort trap: 6 (in target 'App' from project 'App')
        note: reproducer is available at: /tmp/swbuild.tmp.X/Data.noindex
        ** BUILD FAILED **
        """

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("frontend-crash-\(UUID().uuidString)")
    }

    // MARK: - Evidence

    @Test
    func `the stack dump yields the signal, SIL function, primary file and reproducer`() {
        let evidence = FrontendCrashDiagnosis.evidence(in: Self.crashOutput)

        #expect(evidence.signal == 6)
        #expect(evidence.silFunction == "$s4main1fyyF")
        #expect(evidence.primaryFiles == ["/p/View.swift"])
        #expect(evidence.reproducerPaths == ["/tmp/swbuild.tmp.X/Data.noindex"])
        #expect(evidence.argv?.first == "/usr/bin/swift-frontend")
    }

    @Test
    func `a context note keeps the declaration line the compiler prints under it`() {
        let notes = FrontendCrashDiagnosis.evidence(in: Self.crashOutput).contextNotes

        #expect(notes.count == 2)
        #expect(notes.last?.hasPrefix("While emitting IR SIL function") == true)
        #expect(notes.last?.hasSuffix("for 'f()' (at /p/View.swift:12:5)") == true)
    }

    @Test
    func `a build with source errors and no crash marker yields no evidence`() {
        let output = """
            /p/View.swift:3:5: error: cannot find 'x' in scope
            ** BUILD FAILED **
            """
        #expect(FrontendCrashDiagnosis.evidence(in: output).isEmpty)
    }

    // MARK: - Report

    @Test
    func `a crash report names the demangled function and the replay script`() throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A window of zero minutes keeps the test off the .ips files the machine holds.
        let report = try #require(FrontendCrashDiagnosis.diagnose(
            output: Self.crashOutput,
            reportedErrorCount: 0,
            derivedDataPath: nil,
            windowMinutes: 0,
            crashDirectory: directory,
        ))

        #expect(report.hasPrefix("Compiler crash: swift-frontend died on signal 6"))
        #expect(report.contains("Crashing function: main.f() -> ()"))
        #expect(report.contains("mangled: $s4main1fyyF"))
        #expect(report.contains("  /p/View.swift"))
        #expect(report.contains("Reproducer: /tmp/swbuild.tmp.X/Data.noindex"))
        #expect(report.contains("replay.sh"))
    }

    @Test
    func `a failure with source errors and no crash marker yields no report`() {
        let report = FrontendCrashDiagnosis.diagnose(
            output: "/p/View.swift:3:5: error: cannot find 'x' in scope\n** BUILD FAILED **",
            reportedErrorCount: 1,
            derivedDataPath: nil,
            windowMinutes: 0,
            crashDirectory: scratchDirectory(),
        )
        #expect(report == nil)
    }

    @Test
    func `a symbol the runtime cannot demangle comes back unchanged`() {
        #expect(FrontendCrashDiagnosis.demangle("not_a_swift_symbol") == "not_a_swift_symbol")
    }

    // MARK: - Empty build log

    @Test
    func `an empty build log falls back to the dia files the build wrote`() throws {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let objects = root.appendingPathComponent(
            "Build/Intermediates.noindex/App.build/Debug/App.build/Objects-normal/arm64",
        )
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        let dia = objects.appendingPathComponent("View.dia")
        try FileManager.default.copyItem(at: TestFixtures.url("sample-diagnostics.dia"), to: dia)
        // A copy keeps the fixture's date. The fallback reads only files the build just wrote.
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: dia.path,
        )

        let emptyLog = BuildLogEntry(path: "/x.xcactivitylog", date: Date())
        let report = EmptyBuildLogFallback.report(
            derivedDataPath: root.path,
            emptyLog: emptyLog,
            staleLog: BuildLogEntry(path: "/old.xcactivitylog", date: .distantPast),
            errorsOnly: true,
        )

        #expect(report.contains("is empty"))
        #expect(report.contains("from an earlier build"))
        #expect(report.contains("**2 errors:**"))
        #expect(report.contains("cannot find 'undefinedName' in scope"))
    }
}
