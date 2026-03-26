import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

struct XctraceRecordToolTests {
    @Test
    func `Tool schema has correct name and description`() {
        let tool = XctraceRecordTool(sessionManager: SessionManager())
        let schema = tool.tool()

        #expect(schema.name == "xctrace_record")
        #expect(schema.description?.contains("xctrace") == true)
        #expect(schema.description?.contains("trace") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
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

    @Test
    func `Execute with no action throws invalidParams`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test
    func `Execute with invalid action throws invalidParams`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("invalid")])
        }
    }

    @Test
    func `Start without template throws invalidParams`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("start")])
        }
    }

    @Test
    func `Stop without session_id throws invalidParams`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["action": .string("stop")])
        }
    }

    @Test
    func `Stop with invalid session_id throws invalidParams`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "action": .string("stop"),
                "session_id": .string("nonexistent-session-id"),
            ])
        }
    }

    @Test
    func `List with no active sessions returns empty message`() async throws {
        let tool = XctraceRecordTool(sessionManager: SessionManager())

        let result = try await tool.execute(arguments: ["action": .string("list")])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("No active"))
    }
}

struct XctraceListToolTests {
    @Test
    func `tool schema`() {
        let tool = XctraceListTool()
        let schema = tool.tool()

        #expect(schema.name == "xctrace_list")
        #expect(schema.description?.contains("Instruments") == true)
    }

    @Test
    func `Tool schema includes kind parameter`() {
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

    @Test
    func `Execute with no kind throws invalidParams`() async throws {
        let tool = XctraceListTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test
    func `Execute with invalid kind throws invalidParams`() async throws {
        let tool = XctraceListTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["kind": .string("invalid")])
        }
    }

    @Test
    func `List templates returns results`() async throws {
        let tool = XctraceListTool()
        let result = try await tool.execute(arguments: ["kind": .string("templates")])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(!text.isEmpty)
    }
}

struct XctraceExportToolTests {
    @Test
    func toolSchema() {
        let tool = XctraceExportTool()
        let schema = tool.tool()

        #expect(schema.name == "xctrace_export")
        #expect(schema.description?.contains("Export") == true)
        #expect(schema.description?.contains(".trace") == true)
    }

    @Test
    func `tool parameters`() {
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

    @Test
    func `Execute with no input_path throws invalidParams`() async throws {
        let tool = XctraceExportTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test
    func `Execute with invalid path throws error`() async throws {
        let tool = XctraceExportTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "input_path": .string("/nonexistent/path.trace"),
            ])
        }
    }
}

struct SampleMacAppToolTests {
    @Test
    func toolSchema() {
        let tool = SampleMacAppTool()
        let schema = tool.tool()

        #expect(schema.name == "sample_mac_app")
        #expect(schema.description?.contains("Sample") == true)
        #expect(schema.description?.contains("call stacks") == true)
    }

    @Test
    func `Tool schema includes expected parameters`() {
        let tool = SampleMacAppTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["pid"] != nil)
        #expect(properties["bundle_id"] != nil)
        #expect(properties["duration"] != nil)
        #expect(properties["interval"] != nil)
    }

    @Test
    func `Execute with no pid or bundle_id throws invalidParams`() async throws {
        let tool = SampleMacAppTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test
    func `Execute with invalid bundle_id throws invalidParams`() async throws {
        let tool = SampleMacAppTool()

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [
                "bundle_id": .string("com.nonexistent.app.12345"),
            ])
        }
    }
}

struct ProfileAppLaunchToolTests {
    @Test
    func toolSchema() {
        let tool = ProfileAppLaunchTool(sessionManager: SessionManager())
        let schema = tool.tool()

        #expect(schema.name == "profile_app_launch")
        #expect(schema.description?.contains("launch") == true)
        #expect(schema.description?.contains("profile") == true || schema.description?
            .contains("Profile") == true)
    }

    @Test
    func `Tool schema includes expected parameters`() {
        let tool = ProfileAppLaunchTool(sessionManager: SessionManager())
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["project_path"] != nil)
        #expect(properties["workspace_path"] != nil)
        #expect(properties["scheme"] != nil)
        #expect(properties["configuration"] != nil)
        #expect(properties["template"] != nil)
        #expect(properties["duration"] != nil)
    }
}
