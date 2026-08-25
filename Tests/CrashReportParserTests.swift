import Testing
import Foundation
@testable import XCMCPCore

struct CrashReportParserTests {
    /// Parses a JSON body literal the way ``CrashReportParser/parse(jsonBody:)`` takes it.
    private func parse(_ json: String) throws -> CrashReportParser.CrashSummary {
        try CrashReportParser.parse(jsonBody: Data(json.utf8))
    }

    @Test
    func `A compiler crash reports the fault address and the crashing frames`() throws {
        // The exception subtype carries the fault address, which is what separates a corrupt
        // pointer from a stack overflow. The frames name the failing LLVM pass.
        let summary = try parse(
            """
            {
              "procName": "swift-frontend",
              "exception": {
                "type": "EXC_BAD_ACCESS",
                "subtype": "KERN_INVALID_ADDRESS at 0x00000000532a2140",
                "signal": "SIGSEGV"
              },
              "faultingThread": 0,
              "usedImages": [{ "name": "swift-frontend" }],
              "threads": [
                {
                  "frames": [
                    {
                      "imageIndex": 0,
                      "symbol": "llvm::GEPOperator::accumulateConstantOffset",
                      "symbolLocation": 84
                    },
                    {
                      "imageIndex": 0,
                      "symbol": "llvm::PostOrderFunctionAttrsPass::run",
                      "symbolLocation": 212
                    }
                  ]
                }
              ]
            }
            """)

        #expect(summary.exceptionType == "EXC_BAD_ACCESS")
        #expect(summary.exceptionSubtype == "KERN_INVALID_ADDRESS at 0x00000000532a2140")
        #expect(summary.crashingThreadFrames.count == 2)

        let formatted = summary.formatted()
        #expect(formatted.contains("0x00000000532a2140"))
        #expect(formatted.contains("PostOrderFunctionAttrsPass"))
    }

    @Test
    func `A report without an exception subtype still formats`() throws {
        let summary = try parse(
            """
            {
              "procName": "swift-frontend",
              "exception": { "type": "EXC_BAD_ACCESS", "signal": "SIGSEGV" }
            }
            """)

        #expect(summary.exceptionSubtype == nil)
        #expect(summary.formatted().contains("EXC_BAD_ACCESS"))
    }

    @Test
    func `Parses JSON with termination reason and exception`() throws {
        let summary = try parse(
            """
            {
              "procName": "ThesisApp",
              "captureTime": "2026-02-22 18:17:24.2324 -0700",
              "bundleInfo": { "CFBundleIdentifier": "com.toba.thesis" },
              "exception": { "type": "EXC_CRASH", "signal": "SIGABRT" },
              "termination": {
                "namespace": "DYLD",
                "indicator": "Symbol missing",
                "reasons": [
                  "Symbol not found: _$s4Core10DiagnosticCN",
                  "Referenced from: /path/to/ThesisApp"
                ],
                "details": ["(terminated at launch; ignore backtrace)"]
              },
              "fatalDyldError": 1
            }
            """)

        #expect(summary.processName == "ThesisApp")
        #expect(summary.bundleID == "com.toba.thesis")
        #expect(summary.exceptionType == "EXC_CRASH")
        #expect(summary.signal == "SIGABRT")
        #expect(summary.terminationNamespace == "DYLD")
        #expect(summary.terminationIndicator == "Symbol missing")
        #expect(summary.terminationReasons.count == 2)
        #expect(summary.terminationReasons[0].contains("Symbol not found"))
        #expect(summary.terminationDetails.count == 1)
        #expect(summary.isFatalDyldError)

        let formatted = summary.formatted()
        #expect(formatted.contains("Process: ThesisApp"))
        #expect(formatted.contains("EXC_CRASH"))
        #expect(formatted.contains("SIGABRT"))
        #expect(formatted.contains("DYLD — Symbol missing"))
        #expect(formatted.contains("Symbol not found"))
    }

    @Test
    func `Parses minimal JSON with only process name`() throws {
        let summary = try parse(#"{ "procName": "MyApp" }"#)

        #expect(summary.processName == "MyApp")
        #expect(summary.exceptionType == nil)
        #expect(summary.signal == nil)
        #expect(summary.terminationReasons.isEmpty)
        #expect(!summary.isFatalDyldError)

        let formatted = summary.formatted()
        #expect(formatted == "Process: MyApp")
    }

    @Test
    func `Empty JSON produces empty formatted string`() throws {
        let summary = try parse("{}")
        #expect(summary.processName == nil)
        #expect(summary.formatted().isEmpty)
    }

    @Test
    func `A body that is not an object throws`() {
        // The old dictionary entry point returned an all-nil summary here, which reads as a crash
        // that carried nothing rather than as a body this parser could not read.
        #expect(throws: (any Error).self) { try parse("[]") }
    }

    @Test
    func `A field of the wrong type throws`() {
        #expect(throws: (any Error).self) { try parse(#"{ "procName": 42 }"#) }
    }

    @Test
    func `fatalDyldError adds hint when no DYLD in termination`() throws {
        let summary = try parse(#"{ "procName": "CrashApp", "fatalDyldError": 1 }"#)

        #expect(summary.isFatalDyldError)
        let formatted = summary.formatted()
        #expect(formatted.contains("Fatal dyld error"))
    }

    @Test
    func `fatalDyldError does not duplicate when DYLD already in termination`() throws {
        let summary = try parse(
            """
            {
              "procName": "CrashApp",
              "fatalDyldError": 1,
              "termination": { "namespace": "DYLD", "indicator": "Symbol missing" }
            }
            """)

        let formatted = summary.formatted()
        #expect(formatted.contains("DYLD — Symbol missing"))
        #expect(!formatted.contains("Fatal dyld error"))
    }

    @Test
    func `Parses crashing thread stack frames`() throws {
        let summary = try parse(
            """
            {
              "procName": "CrashApp",
              "faultingThread": 2,
              "exception": { "type": "EXC_BREAKPOINT", "signal": "SIGTRAP" },
              "usedImages": [{ "name": "CrashApp" }, { "name": "Swift" }, { "name": "CoreFoundation" }],
              "threads": [
                { "frames": [] },
                { "frames": [] },
                {
                  "frames": [
                    { "imageIndex": 1, "symbol": "_assertionFailure", "symbolLocation": 100 },
                    {
                      "imageIndex": 0,
                      "symbol": "Diagnostic.log(_:for:file:method:line:showInConsole:fail:as:)",
                      "symbolLocation": 356,
                      "sourceFile": "Diagnostic.swift",
                      "sourceLine": 152
                    },
                    { "imageIndex": 2, "symbol": "CFRunLoopRun", "symbolLocation": 42 }
                  ]
                }
              ]
            }
            """)

        #expect(summary.crashingThread == 2)
        #expect(summary.crashingThreadFrames.count == 3)

        let frame0 = summary.crashingThreadFrames[0]
        #expect(frame0.imageName == "Swift")
        #expect(frame0.symbol == "_assertionFailure")
        #expect(frame0.symbolOffset == 100)

        let frame1 = summary.crashingThreadFrames[1]
        #expect(frame1.imageName == "CrashApp")
        #expect(frame1.sourceFile == "Diagnostic.swift")
        #expect(frame1.sourceLine == 152)

        let formatted = summary.formatted()
        #expect(formatted.contains("Crashing Thread 2:"))
        #expect(formatted.contains("Swift  _assertionFailure +100"))
        #expect(formatted.contains("Diagnostic.swift:152"))
    }

    @Test
    func `No crashing thread when faultingThread missing`() throws {
        let summary = try parse(#"{ "procName": "NoCrashApp" }"#)
        #expect(summary.crashingThread == nil)
        #expect(summary.crashingThreadFrames.isEmpty)
        #expect(!summary.formatted().contains("Crashing Thread"))
    }

    @Test
    func `Search returns empty for nonexistent process`() {
        let results = CrashReportParser.search(
            processName: "NonExistentApp_\(UUID().uuidString)",
            minutes: 1,
        )
        #expect(results.isEmpty)
    }

    @Test
    func `diagnosticReportsDir points to expected location`() {
        let dir = CrashReportParser.diagnosticReportsDir
        #expect(dir.contains("Library/Logs/DiagnosticReports"))
    }

    // MARK: - SearchDiagnostics

    @Test
    func `searchWithDiagnostics returns nil diagnostics when results found`() {
        // Search without filters — if any reports exist, diagnostics should be nil
        let (_, diagnostics) = CrashReportParser.searchWithDiagnostics(minutes: 0)
        #expect(diagnostics == nil)
    }

    @Test
    func `searchWithDiagnostics returns diagnostics for missing process`() {
        let (results, diagnostics) = CrashReportParser.searchWithDiagnostics(
            processName: "NonExistentApp_\(UUID().uuidString)",
            minutes: 1,
        )
        #expect(results.isEmpty)
        // Diagnostics should be non-nil since we specified a filter
        #expect(diagnostics != nil)
        #expect(diagnostics?.totalReportsForProcess == 0)
        #expect(diagnostics?.throttleLikely == false)
    }
}
