import MCP
import Testing

@testable import XCMCPTools

@Suite("DebugViewBordersTool Tests")
struct DebugViewBordersToolTests {
    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = DebugViewBordersTool()
        let schema = tool.tool()

        #expect(schema.name == "debug_view_borders")
        #expect(schema.description?.contains("borders") == true)
        #expect(schema.description?.contains("LLDB") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
        let tool = DebugViewBordersTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
            case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["pid"] != nil)
        #expect(properties["bundle_id"] != nil)
        #expect(properties["enabled"] != nil)
        #expect(properties["border_width"] != nil)
        #expect(properties["color"] != nil)
    }

    @Test("Execute with no pid or bundle_id throws invalidParams")
    func noPidOrBundleId() async throws {
        let tool = DebugViewBordersTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["enabled": .bool(true)])
        }
    }

    @Test("Execute with missing enabled throws invalidParams")
    func missingEnabled() async throws {
        let tool = DebugViewBordersTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["pid": .int(12345)])
        }
    }
}
