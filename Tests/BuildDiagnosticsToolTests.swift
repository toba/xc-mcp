import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

// MARK: - CheckOutputFileMapTool

struct CheckOutputFileMapToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = CheckOutputFileMapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "check_output_file_map")
        #expect(schema.description?.contains("OutputFileMap") == true)
        #expect(schema.description?.contains("silent compiler crash") == true)
    }

    @Test
    func `Tool schema requires target parameter`() {
        let tool = CheckOutputFileMapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected object input schema with required array")
            return
        }

        #expect(required.contains(.string("target")))
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = CheckOutputFileMapTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["target"] != nil)
        #expect(properties["project_path"] != nil)
        #expect(properties["workspace_path"] != nil)
        #expect(properties["scheme"] != nil)
        #expect(properties["configuration"] != nil)
    }

    @Test
    func `Tool has readOnly annotation`() {
        let tool = CheckOutputFileMapTool(sessionManager: sessionManager)
        let schema = tool.tool()
        #expect(schema.annotations.readOnlyHint == true)
    }
}

// MARK: - ExtractCrashTracesTool

struct ExtractCrashTracesToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = ExtractCrashTracesTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "extract_crash_traces")
        #expect(schema.description?.contains("crash") == true)
        #expect(schema.description?.contains("build log") == true)
    }

    @Test
    func `Tool schema includes max_logs parameter`() {
        let tool = ExtractCrashTracesTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"],
              case let .object(maxLogsProp) = properties["max_logs"]
        else {
            Issue.record("Expected max_logs property")
            return
        }

        #expect(maxLogsProp["type"] == .string("integer"))
    }

    @Test
    func `Tool has no required parameters`() {
        let tool = ExtractCrashTracesTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected required array")
            return
        }

        #expect(required.isEmpty)
    }
}

// MARK: - ListBuildPhaseStatusTool

struct ListBuildPhaseStatusToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = ListBuildPhaseStatusTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "list_build_phase_status")
        #expect(schema.description?.contains("build phases") == true)
        #expect(schema.description?.contains("completed") == true || schema.description?
            .contains("skipped") == true)
    }

    @Test
    func `Tool schema includes optional target filter`() {
        let tool = ListBuildPhaseStatusTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["target"] != nil)
        #expect(properties["project_path"] != nil)
        #expect(properties["scheme"] != nil)
    }

    @Test
    func `Target parameter is optional`() {
        let tool = ListBuildPhaseStatusTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected required array")
            return
        }

        #expect(!required.contains(.string("target")))
    }
}

// MARK: - ReadSerializedDiagnosticsTool

struct ReadSerializedDiagnosticsToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = ReadSerializedDiagnosticsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "read_serialized_diagnostics")
        #expect(schema.description?.contains(".dia") == true)
        #expect(schema.description?.contains("diagnostics") == true)
    }

    @Test
    func `Tool schema includes target and dia_path parameters`() {
        let tool = ReadSerializedDiagnosticsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["target"] != nil)
        #expect(properties["dia_path"] != nil)
        #expect(properties["errors_only"] != nil)
    }

    @Test
    func `Tool fails without target or dia_path`() async throws {
        let tool = ReadSerializedDiagnosticsTool(sessionManager: sessionManager)
        do {
            _ = try await tool.execute(arguments: [:])
            Issue.record("Expected error when neither target nor dia_path provided")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("target") || message.contains("dia_path"))
        }
    }

    @Test
    func `Tool fails with nonexistent dia_path`() async throws {
        let tool = ReadSerializedDiagnosticsTool(sessionManager: sessionManager)
        do {
            _ = try await tool.execute(arguments: [
                "dia_path": .string("/nonexistent/path/file.dia"),
            ])
            Issue.record("Expected error for nonexistent file")
        } catch {
            let message = String(describing: error)
            #expect(message.contains("not found") || message.contains("nonexistent"))
        }
    }
}

// MARK: - DiffBuildSettingsTool

struct DiffBuildSettingsToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = DiffBuildSettingsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "diff_build_settings")
        #expect(schema.description?.contains("Compare") == true || schema.description?
            .contains("diff") == true)
    }

    @Test
    func `Tool schema requires target_a and target_b`() {
        let tool = DiffBuildSettingsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected required array")
            return
        }

        #expect(required.contains(.string("target_a")))
        #expect(required.contains(.string("target_b")))
    }

    @Test
    func `Tool schema includes filter and configuration parameters`() {
        let tool = DiffBuildSettingsTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["target_a"] != nil)
        #expect(properties["target_b"] != nil)
        #expect(properties["configuration_a"] != nil)
        #expect(properties["configuration_b"] != nil)
        #expect(properties["filter"] != nil)
    }
}

// MARK: - ShowBuildDependencyGraphTool

struct ShowBuildDependencyGraphToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = ShowBuildDependencyGraphTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "show_build_dependency_graph")
        #expect(schema.description?.contains("dependency") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
        let tool = ShowBuildDependencyGraphTool(sessionManager: sessionManager)
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
    }

    @Test
    func `Tool has no required parameters`() {
        let tool = ShowBuildDependencyGraphTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected required array")
            return
        }

        #expect(required.isEmpty)
    }

    @Test
    func `Tool has readOnly annotation`() {
        let tool = ShowBuildDependencyGraphTool(sessionManager: sessionManager)
        let schema = tool.tool()
        #expect(schema.annotations.readOnlyHint == true)
    }
}
