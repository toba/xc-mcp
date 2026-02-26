import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

@Suite("GetTestAttachmentsTool Tests")
struct GetTestAttachmentsToolTests {
    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        #expect(schema.name == "get_test_attachments")
        #expect(schema.description?.contains("attachments") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["result_bundle_path"] != nil)
        #expect(properties["test_id"] != nil)
        #expect(properties["output_path"] != nil)
        #expect(properties["only_failures"] != nil)
    }

    @Test("Tool schema requires result_bundle_path")
    func requiredParams() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected object input schema with required array")
            return
        }

        #expect(required.contains(.string("result_bundle_path")))
    }

    @Test("Execute with missing result_bundle_path throws invalidParams")
    func missingRequiredParam() async {
        let tool = GetTestAttachmentsTool()
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute with nonexistent path throws invalidParams")
    func nonexistentPath() async {
        let tool = GetTestAttachmentsTool()
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/nonexistent/path.xcresult"),
            ])
        }
    }
}
