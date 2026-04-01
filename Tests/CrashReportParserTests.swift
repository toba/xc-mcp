import Testing
@testable import XCMCPCore
import Foundation

struct CrashReportParserTests {
    @Test
    func `Parses JSON with termination reason and exception`() {
        let json: [String: Any] = [
            "procName": "ThesisApp",
            "captureTime": "2026-02-22 18:17:24.2324 -0700",
            "bundleInfo": ["CFBundleIdentifier": "com.toba.thesis"] as [String: Any],
            "exception": [
                "type": "EXC_CRASH",
                "signal": "SIGABRT",
            ] as [String: Any],
            "termination": [
                "namespace": "DYLD",
                "indicator": "Symbol missing",
                "reasons": [
                    "Symbol not found: _$s4Core10DiagnosticCN",
                    "Referenced from: /path/to/ThesisApp",
                ],
                "details": [
                    "(terminated at launch; ignore backtrace)",
                ],
            ] as [String: Any],
            "fatalDyldError": 1,
        ]

        let summary = CrashReportParser.parseJSON(json)
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
    func `Parses minimal JSON with only process name`() {
        let json: [String: Any] = [
            "procName": "MyApp",
        ]

        let summary = CrashReportParser.parseJSON(json)
        #expect(summary.processName == "MyApp")
        #expect(summary.exceptionType == nil)
        #expect(summary.signal == nil)
        #expect(summary.terminationReasons.isEmpty)
        #expect(!summary.isFatalDyldError)

        let formatted = summary.formatted()
        #expect(formatted == "Process: MyApp")
    }

    @Test
    func `Empty JSON produces empty formatted string`() {
        let summary = CrashReportParser.parseJSON([:])
        #expect(summary.processName == nil)
        #expect(summary.formatted().isEmpty)
    }

    @Test
    func `fatalDyldError adds hint when no DYLD in termination`() {
        let json: [String: Any] = [
            "procName": "CrashApp",
            "fatalDyldError": 1,
        ]

        let summary = CrashReportParser.parseJSON(json)
        #expect(summary.isFatalDyldError)
        let formatted = summary.formatted()
        #expect(formatted.contains("Fatal dyld error"))
    }

    @Test
    func `fatalDyldError does not duplicate when DYLD already in termination`() {
        let json: [String: Any] = [
            "procName": "CrashApp",
            "fatalDyldError": 1,
            "termination": [
                "namespace": "DYLD",
                "indicator": "Symbol missing",
            ] as [String: Any],
        ]

        let summary = CrashReportParser.parseJSON(json)
        let formatted = summary.formatted()
        #expect(formatted.contains("DYLD — Symbol missing"))
        #expect(!formatted.contains("Fatal dyld error"))
    }

    @Test
    func `Parses crashing thread stack frames`() {
        let json: [String: Any] = [
            "procName": "CrashApp",
            "faultingThread": 2,
            "exception": [
                "type": "EXC_BREAKPOINT",
                "signal": "SIGTRAP",
            ] as [String: Any],
            "usedImages": [
                ["name": "CrashApp"],
                ["name": "Swift"],
                ["name": "CoreFoundation"],
            ] as [[String: Any]],
            "threads": [
                ["frames": []] as [String: Any],
                ["frames": []] as [String: Any],
                [
                    "frames": [
                        [
                            "imageIndex": 1,
                            "symbol": "_assertionFailure",
                            "symbolLocation": 100,
                        ] as [String: Any],
                        [
                            "imageIndex": 0,
                            "symbol": "Diagnostic.log(_:for:file:method:line:showInConsole:fail:as:)",
                            "symbolLocation": 356,
                            "sourceFile": "Diagnostic.swift",
                            "sourceLine": 152,
                        ] as [String: Any],
                        [
                            "imageIndex": 2,
                            "symbol": "CFRunLoopRun",
                            "symbolLocation": 42,
                        ] as [String: Any],
                    ],
                ] as [String: Any],
            ] as [[String: Any]],
        ]

        let summary = CrashReportParser.parseJSON(json)
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
    func `No crashing thread when faultingThread missing`() {
        let json: [String: Any] = [
            "procName": "NoCrashApp",
        ]
        let summary = CrashReportParser.parseJSON(json)
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
}
