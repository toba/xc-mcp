import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
struct SwiftLintToolTests {
    let sessionManager = SessionManager()

    /// Source that trips two `sm lint` naming rules.
    static let violatingSource = """
        let Bad_Name = 1
        struct s {}
        """

    @Test
    func `Tool schema has correct name and description`() {
        let tool = SwiftLintTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "swift_lint")
        #expect(schema.description?.contains("sm") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = SwiftLintTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["paths"] != nil)
        #expect(properties["package_path"] != nil)
    }

    @Test
    func `Parses sm JSON output with violations`() {
        let json = """
            [
              {
                "file": "/path/to/Foo.swift",
                "line": 10,
                "column": 5,
                "severity": "warning",
                "rule": "trailingWhitespace",
                "message": "Lines should not have trailing whitespace"
              },
              {
                "file": "/path/to/Bar.swift",
                "line": 20,
                "column": 1,
                "severity": "error",
                "rule": "forceCast",
                "message": "Force casts should be avoided"
              }
            ]
            """
        let violations = SwiftLintTool.parseJSONOutput(json)
        #expect(violations.count == 2)
        #expect(violations[0].file == "/path/to/Foo.swift")
        #expect(violations[0].line == 10)
        #expect(violations[0].column == 5)
        #expect(violations[0].severity == "warning")
        #expect(violations[0].rule == "trailingWhitespace")
        #expect(violations[1].file == "/path/to/Bar.swift")
        #expect(violations[1].severity == "error")
    }

    @Test
    func `Parses empty JSON array`() {
        let violations = SwiftLintTool.parseJSONOutput("[]")
        #expect(violations.isEmpty)
    }

    @Test
    func `Handles invalid JSON gracefully`() {
        let violations = SwiftLintTool.parseJSONOutput("not json")
        #expect(violations.isEmpty)
    }

    @Test
    func `Formats violations grouped by file`() {
        let violations = [
            SwiftLintTool.Violation(
                file: "/path/to/Foo.swift", line: 10, column: 5,
                severity: "warning", rule: "trailingWhitespace",
                message: "Lines should not have trailing whitespace",
            ),
            SwiftLintTool.Violation(
                file: "/path/to/Foo.swift", line: 20, column: 1,
                severity: "error", rule: "forceCast",
                message: "Force casts should be avoided",
            ),
            SwiftLintTool.Violation(
                file: "/path/to/Bar.swift", line: 5, column: 3,
                severity: "warning", rule: "lineLength",
                message: "Line should be 120 characters or less",
            ),
        ]
        let output = SwiftLintTool.formatViolations(violations)
        #expect(output.contains("3 violation(s) found:"))
        #expect(output.contains("/path/to/Bar.swift"))
        #expect(output.contains("/path/to/Foo.swift"))
        #expect(output.contains("trailingWhitespace"))
        #expect(output.contains("forceCast"))
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `Reports a failure when sm cannot read the paths`() async throws {
        let tool = SwiftLintTool(sessionManager: sessionManager)
        let arguments: [String: Value] = [
            "package_path": .string(TemporaryDirectory.path),
            "paths": .array([.string("DoesNotExistAnywhere")]),
        ]

        await #expect(throws: MCPError.self) { try await tool.execute(arguments: arguments) }
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `Reports a clean verdict for a directory with no violations`() async throws {
        let file = TemporaryDirectory.url.appendingPathComponent("Clean.swift")
        try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let tool = SwiftLintTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "package_path": .string(TemporaryDirectory.path)
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("Code is clean!"))
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `lintSection names the failure when the root does not exist`() async {
        let missing = TemporaryDirectory.url.appendingPathComponent("Missing").path
        let section = await SwiftLintTool.lintSection(forRoot: missing)

        #expect(section?.hasPrefix("## Lint Failed") == true)
        #expect(section?.contains("exit 64") == true)
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `lintSection returns nil for a clean root`() async throws {
        let file = TemporaryDirectory.url.appendingPathComponent("Clean.swift")
        try "let value = 1\n".write(to: file, atomically: true, encoding: .utf8)

        let section = await SwiftLintTool.lintSection(forRoot: TemporaryDirectory.path)

        #expect(section == nil)
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `lintSection reports violations under its own heading`() async throws {
        let file = TemporaryDirectory.url.appendingPathComponent("Violations.swift")
        try Self.violatingSource.write(to: file, atomically: true, encoding: .utf8)

        let section = await SwiftLintTool.lintSection(forRoot: TemporaryDirectory.path)

        #expect(section?.hasPrefix("## Lint Violations") == true)
        #expect(section?.contains("Bad_Name") == true)
    }
}
