import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

@Suite("SwiftFormatTool Tests")
struct SwiftFormatToolTests {
    let sessionManager = SessionManager()

    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = SwiftFormatTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "swift_format")
        #expect(schema.description?.contains("swiftformat") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
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
        #expect(properties["dry_run"] != nil)
    }

    @Test("Parses verbose output with changed files")
    func parseChangedFiles() {
        let output = """
        Running swiftformat...
        *./Sources/Foo.swift
        ./Sources/Bar.swift
        *./Sources/Baz.swift
        """
        let result = SwiftFormatTool.parseVerboseOutput(output)
        #expect(result == ["./Sources/Foo.swift", "./Sources/Baz.swift"])
    }

    @Test("Parses verbose output with no changes")
    func parseNoChanges() {
        let output = """
        Running swiftformat...
        ./Sources/Foo.swift
        ./Sources/Bar.swift
        """
        let result = SwiftFormatTool.parseVerboseOutput(output)
        #expect(result.isEmpty)
    }

    @Test("Parses empty output")
    func parseEmptyOutput() {
        let result = SwiftFormatTool.parseVerboseOutput("")
        #expect(result.isEmpty)
    }
}
