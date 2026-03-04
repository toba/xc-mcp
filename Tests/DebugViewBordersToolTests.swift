import MCP
import Testing
@testable import XCMCPTools

struct DebugViewBordersToolTests {
    @Test
    func `Tool schema has correct name and description`() {
        let tool = DebugViewBordersTool()
        let schema = tool.tool()

        #expect(schema.name == "debug_view_borders")
        #expect(schema.description?.contains("borders") == true)
        #expect(schema.description?.contains("LLDB") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
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

    @Test
    func `Execute with no pid or bundle_id throws invalidParams`() async throws {
        let tool = DebugViewBordersTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["enabled": .bool(true)])
        }
    }

    @Test
    func `Execute with missing enabled throws invalidParams`() async throws {
        let tool = DebugViewBordersTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["pid": .int(12345)])
        }
    }
}
