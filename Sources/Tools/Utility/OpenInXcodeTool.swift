import MCP
import XCMCPCore
import Foundation

/// Opens files, projects, or workspaces in Xcode using `xed`.
///
/// Wraps `/usr/bin/xed` to open files at specific lines, projects, or workspaces
/// in Xcode. Useful for directing the developer to a specific location after
/// diagnosing an issue.
///
/// ## Example
///
/// ```
/// open_in_xcode(path: "/path/to/file.swift", line: 42)
/// open_in_xcode(path: "/path/to/MyApp.xcodeproj")
/// ```
public struct OpenInXcodeTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "open_in_xcode",
            description:
            "Open a file, project, or workspace in Xcode. Optionally jump to a specific line number.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the file, .xcodeproj, or .xcworkspace to open.",
                        ),
                    ]),
                    "line": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Line number to jump to (files only).",
                        ),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let path = try arguments.getRequiredString("path")

        var args: [String] = []
        if let line = arguments.getInt("line") {
            args.append(contentsOf: ["--line", "\(line)"])
        }
        args.append(path)

        let result = try await ProcessResult.run(
            "/usr/bin/xed",
            arguments: args,
            timeout: .seconds(10),
        )

        // xed may return before Xcode is fully ready — that's fine
        if !result.succeeded, result.exitCode != 0 {
            throw MCPError.internalError(
                "xed failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        let fileName = (path as NSString).lastPathComponent
        let lineInfo = arguments.getInt("line").map { " at line \($0)" } ?? ""
        return CallTool.Result(content: [.text(
            text: "Opened \(fileName)\(lineInfo) in Xcode.",
            annotations: nil,
            _meta: nil,
        )])
    }
}
