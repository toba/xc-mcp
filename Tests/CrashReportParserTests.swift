import Foundation
import Testing

@testable import XCMCPCore

@Suite("CrashReportParser Tests")
struct CrashReportParserTests {
  @Test("Parses JSON with termination reason and exception")
  func fullCrashJSON() {
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
          "(terminated at launch; ignore backtrace)"
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

  @Test("Parses minimal JSON with only process name")
  func minimalJSON() {
    let json: [String: Any] = [
      "procName": "MyApp"
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

  @Test("Empty JSON produces empty formatted string")
  func emptyJSON() {
    let summary = CrashReportParser.parseJSON([:])
    #expect(summary.processName == nil)
    #expect(summary.formatted().isEmpty)
  }

  @Test("fatalDyldError adds hint when no DYLD in termination")
  func dyldErrorHint() {
    let json: [String: Any] = [
      "procName": "CrashApp",
      "fatalDyldError": 1,
    ]

    let summary = CrashReportParser.parseJSON(json)
    #expect(summary.isFatalDyldError)
    let formatted = summary.formatted()
    #expect(formatted.contains("Fatal dyld error"))
  }

  @Test("fatalDyldError does not duplicate when DYLD already in termination")
  func dyldErrorNoDuplicate() {
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

  @Test("Search returns empty for nonexistent process")
  func searchNoResults() {
    let results = CrashReportParser.search(
      processName: "NonExistentApp_\(UUID().uuidString)",
      minutes: 1,
    )
    #expect(results.isEmpty)
  }

  @Test("diagnosticReportsDir points to expected location")
  func reportsDir() {
    let dir = CrashReportParser.diagnosticReportsDir
    #expect(dir.contains("Library/Logs/DiagnosticReports"))
  }
}
