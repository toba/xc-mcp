import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

@Suite("StopMacAppTool Tests")
struct StopMacAppToolTests {
    let sessionManager = SessionManager()

    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "stop_mac_app")
        #expect(schema.description?.contains("bundle identifier") == true)
        #expect(schema.description?.contains("process ID") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["bundle_id"] != nil)
        #expect(properties["app_name"] != nil)
        #expect(properties["pid"] != nil)
        #expect(properties["force"] != nil)
    }

    @Test("Execute with no arguments throws invalidParams")
    func noArguments() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test("Stop process by PID with SIGTERM")
    func stopByPID() async throws {
        // Spawn a long-running sleep process to kill
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["300"]
        try process.run()
        let pid = process.processIdentifier

        // Verify the process is running
        #expect(kill(pid, 0) == 0)

        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "pid": .int(Int(pid)),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Successfully stopped"))

        // Verify the process is gone (may take a moment)
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test("Force stop process by PID sends SIGKILL")
    func forceStopByPID() async throws {
        // Spawn a process that ignores SIGTERM
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "trap '' TERM; sleep 300"]
        try process.run()
        let pid = process.processIdentifier

        // Give bash time to set up the trap
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) == 0)

        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "pid": .int(Int(pid)),
            "force": .bool(true),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("forced"))

        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test("Stop non-existent PID reports not running")
    func stopNonExistentPID() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "pid": .int(99999),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("not running"))
    }

    @Test("Graceful kill escalates to SIGKILL on stuck process")
    func gracefulKillEscalatesToSIGKILL() async throws {
        // Spawn a process that ignores SIGTERM
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "trap '' TERM; sleep 300"]
        try process.run()
        let pid = process.processIdentifier

        // Give bash time to set up the trap
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) == 0)

        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "pid": .int(Int(pid)),
            // force: false (default) — should try SIGTERM, timeout, then SIGKILL
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("escalated to SIGKILL"))

        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test("Stop non-existent app by name reports not running")
    func stopNonExistentAppName() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "app_name": .string("NonExistentApp_XCMCPTest_12345"),
        ])

        guard case let .text(message) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("not running"))
    }
}
