import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct SwiftLintToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = SwiftLintTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "swift_lint")
        #expect(schema.description?.contains("swiftlint") == true)
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
        #expect(properties["fix"] != nil)
    }

    @Test
    func `Parses JSON output with violations`() {
        let json = """
        [
          {
            "file": "/path/to/Foo.swift",
            "line": 10,
            "character": 5,
            "severity": "warning",
            "rule_id": "trailing_whitespace",
            "reason": "Lines should not have trailing whitespace"
          },
          {
            "file": "/path/to/Bar.swift",
            "line": 20,
            "character": 1,
            "severity": "error",
            "rule_id": "force_cast",
            "reason": "Force casts should be avoided"
          }
        ]
        """
        let violations = SwiftLintTool.parseJSONOutput(json)
        #expect(violations.count == 2)
        #expect(violations[0].file == "/path/to/Foo.swift")
        #expect(violations[0].line == 10)
        #expect(violations[0].column == 5)
        #expect(violations[0].severity == "warning")
        #expect(violations[0].ruleID == "trailing_whitespace")
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
                severity: "warning", ruleID: "trailing_whitespace",
                reason: "Lines should not have trailing whitespace",
            ),
            SwiftLintTool.Violation(
                file: "/path/to/Foo.swift", line: 20, column: 1,
                severity: "error", ruleID: "force_cast",
                reason: "Force casts should be avoided",
            ),
            SwiftLintTool.Violation(
                file: "/path/to/Bar.swift", line: 5, column: 3,
                severity: "warning", ruleID: "line_length",
                reason: "Line should be 120 characters or less",
            ),
        ]
        let output = SwiftLintTool.formatViolations(violations)
        #expect(output.contains("3 violation(s) found:"))
        #expect(output.contains("/path/to/Bar.swift"))
        #expect(output.contains("/path/to/Foo.swift"))
        #expect(output.contains("trailing_whitespace"))
        #expect(output.contains("force_cast"))
    }
}
