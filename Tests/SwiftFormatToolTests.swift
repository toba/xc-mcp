import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct SwiftFormatToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = SwiftFormatTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "swift_format")
        #expect(schema.description?.contains("sm") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = SwiftFormatTool(sessionManager: sessionManager)
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
    func `Parses sm JSON output with changed files`() {
        let json = """
            {
              "changed": [
                { "file": "/Sources/Foo.swift", "bytes_before": 100, "bytes_after": 110 },
                { "file": "/Sources/Baz.swift", "bytes_before": 200, "bytes_after": 198 }
              ],
              "unchanged": ["/Sources/Bar.swift"],
              "skipped": []
            }
            """
        let summary = SwiftFormatTool.parseJSONOutput(json)
        #expect(summary.changed.count == 2)
        #expect(summary.changed[0].file == "/Sources/Foo.swift")
        #expect(summary.changed[0].bytesBefore == 100)
        #expect(summary.changed[0].bytesAfter == 110)
        #expect(summary.unchanged == ["/Sources/Bar.swift"])
        #expect(summary.skipped.isEmpty)
    }

    @Test
    func `Parses sm JSON output with skipped files`() {
        let json = """
            {
              "changed": [],
              "unchanged": [],
              "skipped": [
                { "file": "/Sources/Bad.swift", "reason": "unparsable" }
              ]
            }
            """
        let summary = SwiftFormatTool.parseJSONOutput(json)
        #expect(summary.changed.isEmpty)
        #expect(summary.skipped.count == 1)
        #expect(summary.skipped[0].file == "/Sources/Bad.swift")
        #expect(summary.skipped[0].reason == "unparsable")
    }

    @Test
    func `Parses empty output`() {
        let summary = SwiftFormatTool.parseJSONOutput("")
        #expect(summary.changed.isEmpty)
        #expect(summary.unchanged.isEmpty)
        #expect(summary.skipped.isEmpty)
    }

    @Test
    func `Handles invalid JSON gracefully`() {
        let summary = SwiftFormatTool.parseJSONOutput("not json")
        #expect(summary.changed.isEmpty)
    }
}
