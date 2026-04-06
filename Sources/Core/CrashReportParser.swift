import Foundation

/// Parses macOS `.ips` crash report files from `~/Library/Logs/DiagnosticReports/`.
///
/// The `.ips` format consists of a JSON header line followed by a JSON body containing
/// exception info, termination reasons, thread backtraces, and loaded images.
public enum CrashReportParser: Sendable {
    /// A single frame in a crashing thread's stack trace.
    public struct StackFrame: Sendable {
        public let index: Int
        public let imageName: String
        public let symbol: String?
        public let symbolOffset: Int?
        public let sourceFile: String?
        public let sourceLine: Int?

        public func formatted() -> String {
            var line = "  \(index)  \(imageName)"
            if let symbol {
                line += "  \(symbol)"
                if let symbolOffset { line += " +\(symbolOffset)" }
            }
            if let sourceFile {
                line += "  \(sourceFile)"
                if let sourceLine { line += ":\(sourceLine)" }
            }
            return line
        }
    }

    /// A summary of a parsed crash report.
    public struct CrashSummary: Sendable {
        public let processName: String?
        public let bundleID: String?
        public let captureTime: String?
        public let exceptionType: String?
        public let signal: String?
        public let terminationNamespace: String?
        public let terminationIndicator: String?
        public let terminationReasons: [String]
        public let terminationDetails: [String]
        public let isFatalDyldError: Bool
        public let crashingThread: Int?
        public let crashingThreadFrames: [StackFrame]

        /// Formats the summary as a human-readable string.
        public func formatted() -> String {
            var parts: [String] = []

            if let processName {
                parts.append("Process: \(processName)")
            }
            if let bundleID {
                parts.append("Bundle ID: \(bundleID)")
            }
            if let captureTime {
                parts.append("Time: \(captureTime)")
            }

            // Exception
            var exParts: [String] = []
            if let exceptionType { exParts.append(exceptionType) }
            if let signal { exParts.append("(\(signal))") }
            if !exParts.isEmpty {
                parts.append("Exception: \(exParts.joined(separator: " "))")
            }

            // Termination — the most actionable part
            if let terminationIndicator {
                let ns = terminationNamespace ?? ""
                parts.append("Termination: \(ns) — \(terminationIndicator)")
            }
            for reason in terminationReasons {
                parts.append("  \(reason)")
            }
            for detail in terminationDetails {
                parts.append("  \(detail)")
            }

            if isFatalDyldError,
               !parts.contains(where: { $0.contains("DYLD") || $0.contains("Symbol") })
            {
                parts.append("Fatal dyld error (missing symbol or library)")
            }

            // Crashing thread stack trace
            if !crashingThreadFrames.isEmpty {
                let threadLabel = crashingThread.map { "Crashing Thread \($0)" } ?? "Crashing Thread"
                var lines = ["\(threadLabel):"]
                for frame in crashingThreadFrames {
                    lines.append(frame.formatted())
                }
                parts.append(lines.joined(separator: "\n"))
            }

            return parts.joined(separator: "\n")
        }
    }

    /// Diagnostic information returned when no crash reports match the search.
    public struct SearchDiagnostics: Sendable {
        /// Process names that had reports in the time window but didn't match the filter.
        public let processesInWindow: [String]
        /// Total all-time report count for the filtered process (if specified).
        public let totalReportsForProcess: Int?
        /// Whether ReportCrash throttling is likely (>= 25 all-time reports, none recent).
        public let throttleLikely: Bool
    }

    /// The directory where macOS stores crash reports.
    public static let diagnosticReportsDir: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports").path

    // MARK: - JSON Models

    /// JSON body of an `.ips` crash report file.
    private struct CrashBody: Decodable {
        let procName: String?
        let captureTime: String?
        let faultingThread: Int?
        let fatalDyldError: Int?
        let exception: ExceptionInfo?
        let termination: TerminationInfo?
        let bundleInfo: BundleInfo?
        let threads: [ThreadInfo]?
        let usedImages: [UsedImage]?
    }

    private struct ExceptionInfo: Decodable {
        let type: String?
        let signal: String?
    }

    private struct TerminationInfo: Decodable {
        let namespace: String?
        let indicator: String?
        let reasons: [String]?
        let details: [String]?
    }

    private struct BundleInfo: Decodable {
        let CFBundleIdentifier: String?
    }

    private struct ThreadInfo: Decodable {
        let frames: [FrameInfo]?
    }

    private struct FrameInfo: Decodable {
        let imageIndex: Int?
        let symbol: String?
        let symbolLocation: Int?
        let sourceFile: String?
        let sourceLine: Int?
    }

    private struct UsedImage: Decodable {
        let name: String?
    }

    /// Parses an `.ips` crash report file at the given path.
    ///
    /// - Parameter path: Absolute path to the `.ips` file.
    /// - Returns: A ``CrashSummary`` if parsing succeeds, `nil` otherwise.
    public static func parse(at path: String) -> CrashSummary? {
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        // .ips files: JSON header on line 1, then the crash body as JSON
        guard let firstNewline = content.firstIndex(of: "\n") else {
            return nil
        }

        let bodyString = String(content[content.index(after: firstNewline)...])
        guard let bodyData = bodyString.data(using: .utf8),
              let body = try? JSONDecoder().decode(CrashBody.self, from: bodyData)
        else {
            return nil
        }

        return makeSummary(from: body)
    }

    /// Parses a crash report from its JSON body dictionary.
    ///
    /// Exposed for testing without needing a file on disk.
    public static func parseJSON(_ json: [String: Any]) -> CrashSummary {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let body = try? JSONDecoder().decode(CrashBody.self, from: data)
        else {
            return CrashSummary(
                processName: nil, bundleID: nil, captureTime: nil,
                exceptionType: nil, signal: nil, terminationNamespace: nil,
                terminationIndicator: nil, terminationReasons: [], terminationDetails: [],
                isFatalDyldError: false, crashingThread: nil, crashingThreadFrames: [],
            )
        }
        return makeSummary(from: body)
    }

    private static func makeSummary(from body: CrashBody) -> CrashSummary {
        let (crashingThread, crashingThreadFrames) = parseCrashingThread(from: body)

        return CrashSummary(
            processName: body.procName,
            bundleID: body.bundleInfo?.CFBundleIdentifier,
            captureTime: body.captureTime,
            exceptionType: body.exception?.type,
            signal: body.exception?.signal,
            terminationNamespace: body.termination?.namespace,
            terminationIndicator: body.termination?.indicator,
            terminationReasons: body.termination?.reasons ?? [],
            terminationDetails: body.termination?.details ?? [],
            isFatalDyldError: body.fatalDyldError != nil && body.fatalDyldError != 0,
            crashingThread: crashingThread,
            crashingThreadFrames: crashingThreadFrames,
        )
    }

    /// Extracts the crashing thread's stack frames from the decoded body.
    private static func parseCrashingThread(
        from body: CrashBody,
    ) -> (threadIndex: Int?, frames: [StackFrame]) {
        guard let faultingThread = body.faultingThread,
              let threads = body.threads,
              faultingThread < threads.count
        else {
            return (nil, [])
        }

        let thread = threads[faultingThread]
        guard let rawFrames = thread.frames else {
            return (faultingThread, [])
        }

        // Resolve image names from usedImages array
        let usedImages = body.usedImages ?? []

        let maxFrames = min(rawFrames.count, 15)
        var frames: [StackFrame] = []
        frames.reserveCapacity(maxFrames)

        for i in 0 ..< maxFrames {
            let raw = rawFrames[i]

            // Resolve image name from imageIndex → usedImages
            var imageName = "???"
            if let imageIndex = raw.imageIndex,
               imageIndex < usedImages.count,
               let name = usedImages[imageIndex].name
            {
                imageName = name
            }

            frames.append(
                StackFrame(
                    index: i,
                    imageName: imageName,
                    symbol: raw.symbol,
                    symbolOffset: raw.symbolLocation,
                    sourceFile: raw.sourceFile,
                    sourceLine: raw.sourceLine,
                ),
            )
        }

        return (faultingThread, frames)
    }

    /// Searches for recent crash reports and appends a formatted summary to the given message.
    ///
    /// Does nothing if no crash reports are found.
    /// - Parameters:
    ///   - message: The string to append the crash report summary to.
    ///   - processName: Optional process name to filter by.
    ///   - bundleID: Optional bundle ID to filter by.
    ///   - minutes: Only include reports from the last N minutes. Defaults to 2.
    public static func appendCrashReports(
        to message: inout String,
        processName: String? = nil,
        bundleID: String? = nil,
        minutes: Int = 2,
    ) {
        let crashes = search(processName: processName, bundleID: bundleID, minutes: minutes)
        guard !crashes.isEmpty else { return }

        message += "\n\n" + String(repeating: "═", count: 60)
        message += "\nCrash Report\(crashes.count == 1 ? "" : "s") Found"
        message += "\n" + String(repeating: "═", count: 60)
        for (i, crash) in crashes.enumerated() {
            if i > 0 {
                message += "\n" + String(repeating: "─", count: 60)
            }
            message += "\nFile: \(crash.path)\n"
            message += crash.summary.formatted()
        }
    }

    /// Searches `~/Library/Logs/DiagnosticReports/` for recent `.ips` crash reports.
    ///
    /// - Parameters:
    ///   - processName: Optional process name to filter by (matched against filename and
    ///     `procName` in the JSON header).
    ///   - bundleID: Optional bundle ID to filter by (matched against the JSON header line).
    ///   - minutes: Only include reports from the last N minutes. Defaults to 5.
    /// - Returns: An array of `(path, summary)` tuples, most recent first.
    public static func search(
        processName: String? = nil,
        bundleID: String? = nil,
        minutes: Int = 5,
    ) -> [(path: String, summary: CrashSummary)] {
        let fm = FileManager.default
        let reportsDir = diagnosticReportsDir

        guard let entries = try? fm.contentsOfDirectory(atPath: reportsDir) else {
            return []
        }

        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        var results: [(path: String, summary: CrashSummary, modified: Date)] = []

        for entry in entries where entry.hasSuffix(".ips") {
            let fullPath = "\(reportsDir)/\(entry)"

            // Filter by recency
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date,
                  modified > cutoff
            else {
                continue
            }

            // Quick filename pre-filter before parsing the full file
            if let processName,
               !entry.localizedCaseInsensitiveContains(processName)
            {
                // Filename doesn't match — still parse to check procName field,
                // but only if no bundle ID filter either
                if bundleID == nil {
                    continue
                }
            }

            guard let summary = parse(at: fullPath) else {
                continue
            }

            // Filter by process name (from parsed JSON)
            if let processName,
               let proc = summary.processName,
               !proc.localizedCaseInsensitiveContains(processName)
            {
                // Filename didn't match and procName didn't match
                if !entry.localizedCaseInsensitiveContains(processName) {
                    continue
                }
            }

            // Filter by bundle ID
            if let bundleID,
               let bid = summary.bundleID,
               bid != bundleID
            {
                continue
            }

            results.append((fullPath, summary, modified))
        }

        // Sort most recent first
        results.sort { $0.modified > $1.modified }
        return results.map { ($0.path, $0.summary) }
    }

    /// Searches for crash reports with diagnostics about why no results were found.
    public static func searchWithDiagnostics(
        processName: String? = nil,
        bundleID: String? = nil,
        minutes: Int = 5,
    ) -> (results: [(path: String, summary: CrashSummary)], diagnostics: SearchDiagnostics?) {
        let results = search(processName: processName, bundleID: bundleID, minutes: minutes)

        guard results.isEmpty, processName != nil || bundleID != nil else {
            return (results, nil)
        }

        let fm = FileManager.default
        let reportsDir = diagnosticReportsDir
        guard let entries = try? fm.contentsOfDirectory(atPath: reportsDir) else {
            return (results, nil)
        }

        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        var totalForProcess = 0
        var processesInWindow: Set<String> = []

        for entry in entries where entry.hasSuffix(".ips") {
            let fullPath = "\(reportsDir)/\(entry)"
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let modified = attrs?[.modificationDate] as? Date
            let isRecent = modified.map { $0 > cutoff } ?? false

            // Check if this file belongs to the filtered process (by filename)
            if let processName {
                if entry.localizedCaseInsensitiveContains(processName) {
                    totalForProcess += 1
                }
            }

            // Collect process names in the time window
            if isRecent {
                // Extract process name from filename (format: ProcessName-date.ips)
                if let dashIndex = entry.firstIndex(of: "-") {
                    let name = String(entry[..<dashIndex])
                    processesInWindow.insert(name)
                }
            }
        }

        let diagnostics = SearchDiagnostics(
            processesInWindow: processesInWindow.sorted(),
            totalReportsForProcess: processName != nil ? totalForProcess : nil,
            throttleLikely: totalForProcess >= 25,
        )

        return (results, diagnostics)
    }
}
