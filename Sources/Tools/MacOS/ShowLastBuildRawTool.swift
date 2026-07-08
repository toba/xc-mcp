import MCP
import XCMCPCore
import Foundation

/// Returns the complete, unparsed combined stdout/stderr of the most recent `xcodebuild` build/test
/// run started through this server.
///
/// Use this when a link failure's parsed summary is truncated or mislabeled and you need the raw
/// `ld` block verbatim — the `Undefined symbols for architecture …` object list, or the
/// `duplicate symbol '…' in:` list of colliding frameworks. That block is the actual diagnosis
/// (which objects/frameworks collide) and can't be recovered from Xcode's `.xcactivitylog` when the
/// failed link step leaves it empty.
///
/// The raw output is captured automatically by `build_macos` / `test_macos` (and the other
/// scheme-based build/test tools) — no flag is required at build time.
public struct ShowLastBuildRawTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "show_last_build_raw",
            description:
            "Return the complete, unparsed clang/ld output of the most recent build/test run. "
                + "Use this to recover the verbatim linker diagnostic (the full "
                + "'Undefined symbols …' / 'duplicate symbol … in:' block with every source path) "
                + "when the parsed build summary truncates or mislabels it. By default returns only "
                + "the compiler/linker diagnostic regions; pass full: true for the entire log.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "full": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "When true, return the entire raw log instead of just the "
                                + "compiler/linker diagnostic regions. Defaults to false.",
                        ),
                    ]),
                    "tail": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Return only the last N lines of the raw log. Takes precedence over the "
                                + "default diagnostic extraction; ignored when full is true.",
                        ),
                    ]),
                ]),
                "required": .array([]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        guard let capture = RawBuildLog.load() else {
            throw MCPError.internalError(
                "No captured build output found. Run build_macos, test_macos, or another "
                    + "scheme-based build/test first — the raw combined output of the most recent "
                    + "run is captured automatically.",
            )
        }

        let full = arguments.getBool("full")
        let tail = arguments.getInt("tail")

        var parts: [String] = [header(for: capture)]

        if full {
            parts.append(body(label: "Full raw log", text: capture.rawOutput))
        } else if let tail, tail > 0 {
            let lines = capture.rawOutput.split(separator: "\n", omittingEmptySubsequences: false)
            let slice = lines.suffix(tail).joined(separator: "\n")
            parts.append(body(label: "Last \(tail) lines", text: slice))
        } else {
            let diagnostics = LinkerDiagnostics.extract(from: capture.rawOutput)
            if diagnostics.isEmpty {
                parts.append(
                    "No compiler or linker diagnostics detected in the captured output. "
                        + "Pass full: true for the entire log, or tail: N for the final lines.",
                )
            } else {
                parts.append(body(label: "Compiler/linker diagnostics", text: diagnostics))
            }
        }

        // Always surface the on-disk path: extraction can miss an unusual diagnostic, but the file
        // holds the complete linker invocation and can be read directly as a last resort.
        parts.append("Full raw log on disk: \(capture.path)")

        return CallTool.Result(
            content: [.text(text: parts.joined(separator: "\n\n"), annotations: nil, _meta: nil)],
        )
    }

    // MARK: - Formatting

    private func header(for capture: RawBuildLog.Capture) -> String {
        guard let meta = capture.metadata else {
            return "## Last build raw output"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let status = meta.succeeded ? "succeeded" : "failed"
        return "## Last build raw output (\(meta.action) — \(status))\n"
            + "Destination: \(meta.destination)\n"
            + "Captured: \(formatter.string(from: meta.capturedAt)) — \(meta.byteCount) bytes"
    }

    private func body(label: String, text: String) -> String {
        "\(label):\n\n```\n\(text)\n```"
    }
}
