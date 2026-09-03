import Foundation
import Synchronization

/// Writes streamed build output to a file, line by line, keeping none of it in memory.
///
/// A verbose compiler probe can emit output far larger than any MCP response holds. Running
/// `-Xllvm -opt-bisect-limit` at full verbosity produced a gigabyte of text whose answer was the
/// last line. This sink takes the chunks as the subprocess produces them, keeps only the lines
/// matching an optional regex, and leaves the caller a path to read instead of a response to
/// truncate.
///
/// Each line loses its terminal escape sequences on the way out, so the file greps like plain text.
///
/// ```swift
/// let sink = try StreamedOutputSink(path: "/tmp/probe.log", filter: "^BISECT")
/// let result = try await runner.build(packagePath: path, onProgress: sink.receive)
/// let summary = sink.finish()
/// ```
public final class StreamedOutputSink: Sendable {
    /// What a finished sink wrote.
    public struct Summary: Sendable {
        /// The file the lines went to.
        public let path: String
        /// Lines the sink saw.
        public let linesSeen: Int
        /// Lines the sink wrote, equal to ``linesSeen`` when no filter is set.
        public let linesWritten: Int
        /// Bytes written to the file.
        public let bytesWritten: Int
        /// The last line the sink wrote, which is the answer for a bisecting probe.
        public let lastLine: String?

        /// A one-paragraph report suitable for an MCP response.
        public func formatted() -> String {
            var text = "Streamed \(linesWritten) of \(linesSeen) lines "
            text += "(\(bytesWritten) bytes) to \(path)."
            if let lastLine { text += "\nLast line written: \(lastLine)" }
            return text
        }
    }

    /// Why a sink could not be created.
    public enum SinkError: Error, CustomStringConvertible {
        case cannotCreateFile(path: String)
        case invalidFilter(pattern: String, underlying: String)

        public var description: String {
            switch self {
                case let .cannotCreateFile(path):
                    "Cannot create the output file at \(path). Check the directory exists and is "
                        + "writable."
                case let .invalidFilter(pattern, underlying):
                    "The filter '\(pattern)' is not a valid regular expression: \(underlying)"
            }
        }
    }

    /// Everything the sink mutates, held under one lock because `onProgress` is a synchronous
    /// callback the subprocess reader can invoke from any thread.
    private struct State {
        var handle: FileHandle?
        var pending = ""
        var linesSeen = 0
        var linesWritten = 0
        var bytesWritten = 0
        var lastLine: String?
        var filter: Regex<AnyRegexOutput>?
    }

    private let state: Mutex<State>
    private let path: String

    /// Creates a sink that writes to `path`.
    ///
    /// - Parameters:
    ///   - path: The file to write. An existing file is truncated.
    ///   - filter: An optional regular expression a line must match to be written.
    /// - Throws: ``SinkError`` when the file cannot be created or the filter does not compile.
    public init(path: String, filter: String?) throws(SinkError) {
        self.path = path

        var compiled: Regex<AnyRegexOutput>?

        if let filter {
            do {
                compiled = try Regex(filter)
            } catch {
                throw SinkError.invalidFilter(pattern: filter, underlying: "\(error)")
            }
        }

        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true,
        )
        guard FileManager.default.createFile(atPath: path, contents: nil),
            let handle = FileHandle(forWritingAtPath: path)
        else { throw SinkError.cannotCreateFile(path: path) }

        var initial = State()
        initial.handle = handle
        initial.filter = compiled
        state = Mutex(initial)
    }

    /// Accepts one chunk of subprocess output.
    ///
    /// A chunk splits at arbitrary byte boundaries, so a trailing partial line is carried into the
    /// next call rather than matched against the filter early.
    ///
    /// The scan walks the chunk once and never removes from the front of a buffer. Removing each
    /// line from the front shifts every byte behind it, which costs time quadratic in the chunk
    /// size, and this sink exists for the gigabyte-scale probe.
    public func receive(_ chunk: String) {
        state.withLock { state in
            guard state.handle != nil else { return }

            var start = chunk.startIndex

            while let newline = chunk[start...].firstIndex(of: "\n") {
                // The carry holds the tail of the previous chunk, so a line split across a chunk
                // boundary reaches the filter whole.
                let line = state.pending.isEmpty
                    ? String(chunk[start..<newline])
                    : state.pending + chunk[start..<newline]
                state.pending = ""
                Self.write(line, to: &state)
                start = chunk.index(after: newline)
            }
            state.pending += chunk[start...]
        }
    }

    /// Flushes the trailing partial line, closes the file and reports what was written.
    public func finish() -> Summary {
        state.withLock { state in
            if !state.pending.isEmpty {
                let line = state.pending
                state.pending = ""
                Self.write(line, to: &state)
            }
            try? state.handle?.close()
            state.handle = nil

            return Summary(
                path: path,
                linesSeen: state.linesSeen,
                linesWritten: state.linesWritten,
                bytesWritten: state.bytesWritten,
                lastLine: state.lastLine,
            )
        }
    }

    private static func write(_ rawLine: String, to state: inout State) {
        state.linesSeen += 1
        // stripping precedes the filter so a colored diagnostic matches a plain pattern
        let line = TerminalEscapes.stripped(rawLine)
        if let filter = state.filter, line.firstMatch(of: filter) == nil { return }

        let data = Data("\(line)\n".utf8)
        try? state.handle?.write(contentsOf: data)
        state.linesWritten += 1
        state.bytesWritten += data.count
        state.lastLine = line
    }
}
