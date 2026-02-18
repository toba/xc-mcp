import MCP
import Testing

@testable import XCMCPCore
@testable import XCMCPTools

@Suite("XctraceRecordTool Tests")
struct XctraceRecordToolTests {
    @Test("Tool schema has correct name and description")
    func testToolSchema() {
        let tool = XctraceRecordTool(sessionManager: SessionManager())
        let schema = tool.tool()

        #expect(schema.name == "xctrace_record")
        #expect(schema.description?.contains("xctrace") == true)
        #expect(schema.description?.contains("trace") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func testToolParameters() {
        let tool = XctraceRecordTool(sessionManager: SessionManager())
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
            case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["action"] != nil)
        #expect(properties["template"] != nil)
        #expect(properties["output_path"] != nil)
        #expect(properties["device"] != nil)
        #expect(properties["time_limit"] != nil)
        #expect(properties["attach_pid"] != nil)
        #expect(properties["attach_name"] != nil)
        #expect(properties["all_processes"] != nil)
        #expect(properties["session_id"] != nil)
    }

    @Test("Execute with no action throws invalidParams")
    func testNoAction() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute with invalid action throws invalidParams")
    func testInvalidAction() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("invalid")])
        }
    }

    @Test("Start without template throws invalidParams")
    func testStartWithoutTemplate() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("start")])
        }
    }

    @Test("Stop without session_id throws invalidParams")
    func testStopWithoutSessionId() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("stop")])
        }
    }

    @Test("Stop with invalid session_id throws invalidParams")
    func testStopWithInvalidSessionId() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "action": .string("stop"),
                "session_id": .string("nonexistent-session-id"),
            ])
        }
    }

    @Test("List with no active sessions returns empty message")
    func testListEmpty() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        let result = try await tool.execute(arguments: ["action": .string("list")])

        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("No active"))
    }
}

@Suite("XctraceListTool Tests")
struct XctraceListToolTests {
    @Test("Tool schema has correct name and description")
    func testToolSchema() {
        let tool = XctraceListTool()
        let schema = tool.tool()

        #expect(schema.name == "xctrace_list")
        #expect(schema.description?.contains("Instruments") == true)
    }

    @Test("Tool schema includes kind parameter")
    func testToolParameters() {
        let tool = XctraceListTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
            case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["kind"] != nil)
    }

    @Test("Execute with no kind throws invalidParams")
    func testNoKind() async throws {
        let tool = XctraceListTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute with invalid kind throws invalidParams")
    func testInvalidKind() async throws {
        let tool = XctraceListTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["kind": .string("invalid")])
        }
    }

    @Test("List templates returns results")
    func testListTemplates() async throws {
        let tool = XctraceListTool()
        let result = try await tool.execute(arguments: ["kind": .string("templates")])

        guard case let .text(text) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(!text.isEmpty)
    }
}

@Suite("XctraceExportTool Tests")
struct XctraceExportToolTests {
    @Test("Tool schema has correct name and description")
    func testToolSchema() {
        let tool = XctraceExportTool()
        let schema = tool.tool()

        #expect(schema.name == "xctrace_export")
        #expect(schema.description?.contains("Export") == true)
        #expect(schema.description?.contains(".trace") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func testToolParameters() {
        let tool = XctraceExportTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
            case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["input_path"] != nil)
        #expect(properties["xpath"] != nil)
        #expect(properties["toc"] != nil)
    }

    @Test("Execute with no input_path throws invalidParams")
    func testNoInputPath() async throws {
        let tool = XctraceExportTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute with invalid path throws error")
    func testInvalidPath() async throws {
        let tool = XctraceExportTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "input_path": .string("/nonexistent/path.trace")
            ])
        }
    }
}
