import MCP
import Testing
import Foundation
@testable import XCMCPCore
@testable import XCMCPTools

@Suite(.temporaryDirectory)
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

    @Test
    func `Rejects a path in another repository`() async {
        let tool = SwiftFormatTool(sessionManager: sessionManager)
        let arguments: [String: Value] = [
            "package_path": .string(TemporaryDirectory.path),
            "paths": .array([.string("/Users/dev/another-repo/Sources")]),
        ]

        await #expect(throws: MCPError.self) { try await tool.execute(arguments: arguments) }
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `Reports a failure when sm cannot read the paths`() async {
        let tool = SwiftFormatTool(sessionManager: sessionManager)
        let arguments: [String: Value] = [
            "package_path": .string(TemporaryDirectory.path),
            "paths": .array([.string("DoesNotExistAnywhere")]),
        ]

        await #expect(throws: MCPError.self) { try await tool.execute(arguments: arguments) }
    }

    @Test(.enabled(if: InstalledSm.isAvailable))
    func `Formats a file named by a relative path inside the package`() async throws {
        let file = TemporaryDirectory.url.appendingPathComponent("Messy.swift")
        try "let x  =  1\n".write(to: file, atomically: true, encoding: .utf8)

        let tool = SwiftFormatTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "package_path": .string(TemporaryDirectory.path),
            "paths": .array([.string("Messy.swift")]),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("Messy.swift"))

        let formatted = try String(contentsOf: file, encoding: .utf8)
        #expect(formatted == "let x = 1\n")
    }
}
