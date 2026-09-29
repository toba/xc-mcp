import Foundation

/// Recognizes a `swift-frontend` crash in an `xcodebuild` build and recovers its cause.
///
/// When the compiler itself dies, the build often reports only `Build failed (N warnings)`. The
/// crash prints no `file:line: error:` line, the activity log can be written empty, and the one
/// `.dia` file for the crashing job holds only a note that a reproducer exists. The cause sits in
/// three other places:
///
/// 1. The LLVM stack dump in the build output. Its `While …` lines name the phase and the SIL
///    function the compiler was working on, and its `Program arguments:` line holds the argv.
/// 2. The `.dia` file of the crashing job, which names the reproducer directory.
/// 3. The `.ips` report macOS writes to `~/Library/Logs/DiagnosticReports`.
///
/// This type reads all three and writes one report. ``CompilerCrashReport`` writes the replay
/// script and reads the `.ips`, so the SwiftPM and `xcodebuild` paths share that half.
public enum FrontendCrashDiagnosis {
    /// What the build output and the `.dia` files say about a crash.
    public struct Evidence: Sendable, Equatable {
        /// The signal the compiler died on, when the output names it.
        public var signal: Int?
        /// The `While …` lines of the stack dump, in dump order.
        public var contextNotes: [String] = []
        /// The mangled SIL function the compiler was emitting or optimizing, without its `@`.
        public var silFunction: String?
        /// The source files the crashing job compiled as primary files.
        public var primaryFiles: [String] = []
        /// The reproducer directories the compiler reported.
        public var reproducerPaths: [String] = []
        /// The whole frontend argv, when the stack dump printed it.
        public var argv: [String]?
        /// The `.dia` files that carried a reproducer note.
        public var diagnosticFiles: [String] = []

        public init() {
            // Every property has a default, so there is nothing to set.
        }

        /// Whether any crash marker turned up.
        public var isEmpty: Bool {
            signal == nil && contextNotes.isEmpty && silFunction == nil
                && reproducerPaths.isEmpty && argv == nil
        }
    }

    // MARK: - Output scan

    /// The signal forms `xcodebuild` prints for a tool that died, such as
    /// `error: Abort trap: 6 (in target 'App' from project 'App')`.
    private static nonisolated(unsafe) let xcodebuildSignalPattern =
        /\b(?:Segmentation fault|Abort trap|Illegal instruction|Trace\/BPT trap|Bus error): (\d+)/

    /// A stack dump entry such as `4.\tWhile emitting IR SIL function "@$s4main1fyyF".`.
    private static nonisolated(unsafe) let contextNotePattern = /^\s*\d+\.\s+(While .+)$/

    /// The SIL function name inside a context note.
    private static nonisolated(unsafe) let silFunctionPattern = /SIL function "@([^"]+)"/

    /// The file an IRGen or type-check request names.
    private static nonisolated(unsafe) let requestFilePattern = /for file "([^"]+\.swift)"/

    /// The reproducer note the compiler prints and serializes into the `.dia` file.
    private static nonisolated(unsafe) let reproducerPattern =
        /reproducer is available at:?\s*(\S.*?)\s*$/

    /// Scans build output for the markers a frontend crash leaves.
    ///
    /// - Parameter output: The combined build output.
    /// - Returns: The evidence found, empty when the output holds no crash marker.
    public static func evidence(in output: String) -> Evidence {
        var evidence = Evidence()
        evidence.signal = ErrorExtractor.detectCompilerCrash(in: output)
        var lastWasContextNote = false

        for line in BuildLogLines.split(output) {
            if evidence.signal == nil, let match = line.firstMatch(of: xcodebuildSignalPattern) {
                evidence.signal = Int(match.1)
            }

            if let match = line.firstMatch(of: contextNotePattern) {
                let note = String(match.1)
                appendUnique([note], to: &evidence.contextNotes)
                recordFiles(in: note, into: &evidence)
                lastWasContextNote = true
                continue
            }

            // The compiler prints the declaration of a context note on the next line, as
            // ` for 'body' (at /path/View.swift:12:5)`.
            if lastWasContextNote, line.hasPrefix(" for "), let last = evidence.contextNotes.last {
                evidence.contextNotes[evidence.contextNotes.count - 1] = last + line
            }
            lastWasContextNote = false

            if let match = line.firstMatch(of: reproducerPattern) {
                appendUnique([String(match.1)], to: &evidence.reproducerPaths)
            }
        }

        if let argv = ErrorExtractor.extractFrontendArguments(from: output) {
            evidence.argv = argv
            appendUnique(primaryFiles(in: argv), to: &evidence.primaryFiles)
        }
        return evidence
    }

    /// Adds the SIL function and the source file a context note names.
    private static func recordFiles(in note: String, into evidence: inout Evidence) {
        if evidence.silFunction == nil, let match = note.firstMatch(of: silFunctionPattern) {
            evidence.silFunction = String(match.1)
        }
        if let match = note.firstMatch(of: requestFilePattern) {
            appendUnique([String(match.1)], to: &evidence.primaryFiles)
        }
    }

    /// Returns the value of each `-primary-file` flag in an argv.
    static func primaryFiles(in argv: [String]) -> [String] {
        var files: [String] = []
        for (index, token) in argv.enumerated()
            where token == "-primary-file" && index + 1 < argv.count
        {
            files.append(argv[index + 1])
        }
        return files
    }

    private static func appendUnique(_ values: [String], to list: inout [String]) {
        for value in values where !list.contains(value) { list.append(value) }
    }

    // MARK: - Serialized diagnostics

    /// Adds the reproducer notes from the `.dia` files a failed build wrote.
    ///
    /// A build tree holds thousands of `.dia` files. Only the ones written in the last
    /// `withinMinutes` minutes are searched, and only the ones whose bytes hold the reproducer
    /// note are decoded.
    ///
    /// - Parameters:
    ///   - evidence: The evidence to add to.
    ///   - intermediatesDirectory: The `Build/Intermediates.noindex` directory of the build.
    ///   - withinMinutes: How recent a `.dia` file must be to count.
    public static func addDiagnosticFileEvidence(
        to evidence: inout Evidence,
        intermediatesDirectory: String,
        withinMinutes: Int = 10,
    ) {
        let cutoff = Date().addingTimeInterval(-Double(withinMinutes * 60))

        for path in recentDiagnosticFiles(in: intermediatesDirectory, since: cutoff)
            where SerializedDiagnostics.fileContains("reproducer is available", atPath: path)
        {
            evidence.diagnosticFiles.append(path)
            guard let diagnostics = try? SerializedDiagnostics.decode(contentsOf: path) else {
                continue
            }
            for diagnostic in diagnostics.flatMap(\.flattened) {
                if let match = diagnostic.message.firstMatch(of: reproducerPattern) {
                    appendUnique([String(match.1)], to: &evidence.reproducerPaths)
                }
                if let file = diagnostic.file, file.hasSuffix(".swift") {
                    appendUnique([file], to: &evidence.primaryFiles)
                }
            }
        }
    }

    /// The `.dia` files under `directory` modified after `cutoff`, newest first.
    static func recentDiagnosticFiles(in directory: String, since cutoff: Date) -> [String] {
        let root = URL(fileURLWithPath: directory)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        ) else { return [] }

        var files: [(path: String, modified: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "dia" {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let modified, modified > cutoff { files.append((url.path, modified)) }
        }
        return files.sorted { $0.modified > $1.modified }.map(\.path)
    }

    // MARK: - Report

    /// Returns a crash report for a failed build, or `nil` when nothing points to a crash.
    ///
    /// A build counts as a compiler crash when its output carries a crash marker, when a recent
    /// `.dia` file carries the reproducer note, or when it failed with no error line and macOS
    /// wrote a `swift-frontend` crash report during the window.
    ///
    /// - Parameters:
    ///   - output: The combined build output.
    ///   - reportedErrorCount: How many errors the build output parser found.
    ///   - derivedDataPath: The DerivedData root of the build, when known.
    ///   - windowMinutes: How far back a `.dia` file or `.ips` report may date.
    ///   - crashDirectory: Where to write the argv file and the replay script.
    public static func diagnose(
        output: String,
        reportedErrorCount: Int,
        derivedDataPath: String?,
        windowMinutes: Int = 10,
        crashDirectory: URL = CompilerCrashReport.defaultDirectory(),
    ) -> String? {
        var evidence = Self.evidence(in: output)

        // Source errors explain a failure on their own. Without a crash marker, the slower
        // `.dia` and `.ips` searches run only for a build that failed with no error line.
        if reportedErrorCount > 0, evidence.isEmpty { return nil }

        if let derivedDataPath {
            addDiagnosticFileEvidence(
                to: &evidence,
                intermediatesDirectory: DerivedDataLocator.intermediatesPath(
                    projectRoot: derivedDataPath,
                ),
                withinMinutes: windowMinutes,
            )
        }

        let artifacts = CompilerCrashReport.write(
            signal: evidence.signal,
            argv: evidence.argv,
            into: crashDirectory,
            reportWindowMinutes: windowMinutes,
        )

        let silentFailureWithReport = reportedErrorCount == 0 && artifacts.crashSummary != nil
        guard !evidence.isEmpty || silentFailureWithReport else { return nil }

        return format(evidence, artifacts: artifacts)
    }

    /// Renders the evidence and the artifacts as one report.
    static func format(_ evidence: Evidence, artifacts: CompilerCrashReport.Artifacts) -> String {
        var header = "Compiler crash: swift-frontend died"
        if let signal = evidence.signal {
            header += " on signal \(signal)"
            if let name = strsignal(Int32(signal)) { header += " (\(String(cString: name)))" }
        }
        header += ". The compiler printed no source error for it, so the warning and error "
            + "counts below do not explain the failure."
        var sections = [header]

        if let mangled = evidence.silFunction {
            let demangled = demangle(mangled)
            sections.append(
                demangled == mangled
                    ? "Crashing function: \(mangled)"
                    : "Crashing function: \(demangled)\n  mangled: \(mangled)",
            )
        }

        if !evidence.primaryFiles.isEmpty {
            sections.append(titledList("Primary file(s):", evidence.primaryFiles))
        }

        if !evidence.contextNotes.isEmpty {
            sections.append(
                titledList("Compiler context (from the stack dump):", evidence.contextNotes),
            )
        }

        for path in evidence.reproducerPaths {
            var reproducer = "Reproducer: \(path)"
            let script = URL(fileURLWithPath: path).appendingPathComponent("reproduce.sh").path
            if FileManager.default.fileExists(atPath: script) {
                reproducer += "\n  Replay it with: sh \(script)"
            }
            sections.append(reproducer)
        }

        if !evidence.diagnosticFiles.isEmpty {
            sections.append(
                titledList("Serialized diagnostics with the crash note:", evidence.diagnosticFiles),
            )
        }

        let report = artifacts.formatted()
        if !report.isEmpty { sections.append(report) }

        if evidence.silFunction == nil, artifacts.crashSummary == nil {
            sections.append(
                "No stack dump or OS crash report named the crashing function. "
                    + "Run search_crash_reports with process_name swift-frontend.",
            )
        }
        return sections.joined(separator: "\n\n")
    }

    /// A title line, then one indented line per item.
    private static func titledList(_ title: String, _ items: [String]) -> String {
        title + "\n" + items.lazy.map { "  \($0)" }.joined(separator: "\n")
    }

    // MARK: - Demangling

    /// Demangles a Swift symbol, returning it unchanged when the runtime cannot.
    public static func demangle(_ mangled: String) -> String {
        let length = mangled.utf8.count
        let result = mangled.withCString { pointer in
            swiftDemangle(pointer, length, nil, nil, 0)
        }
        guard let result else { return mangled }
        defer { free(result) }
        return String(cString: result)
    }
}

/// The Swift runtime entry point that demangles a symbol into a `malloc`ed C string.
@_silgen_name("swift_demangle")
private func swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32,
) -> UnsafeMutablePointer<CChar>?
