import MCP
import Testing
@testable import XCMCPCore
import Foundation
@testable import XCMCPTools

struct StopMacAppToolTests {
    let sessionManager = SessionManager()

    @Test
    func `Tool schema has correct name and description`() {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let schema = tool.tool()

        #expect(schema.name == "stop_mac_app")
        #expect(schema.description?.contains("bundle identifier") == true)
        #expect(schema.description?.contains("process ID") == true)
    }

    @Test
    func `Tool schema includes all expected parameters`() {
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

    @Test
    func `Execute with no arguments throws invalidParams`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)

        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: [:])
        }
    }

    @Test
    func `Stop process by PID with SIGTERM`() async throws {
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("Successfully stopped"))

        // Verify the process is gone (may take a moment)
        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test
    func `Force stop process by PID sends SIGKILL`() async throws {
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("forced"))

        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test
    func `Stop non-existent PID reports not running`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "pid": .int(99999),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("not running"))
    }

    @Test
    func `Graceful kill escalates to SIGKILL on stuck process`() async throws {
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

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("escalated to SIGKILL"))

        try await Task.sleep(for: .milliseconds(200))
        #expect(kill(pid, 0) != 0)
    }

    @Test
    func `Stop non-existent app by name reports not running`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        let result = try await tool.execute(arguments: [
            "app_name": .string("NonExistentApp_XCMCPTest_12345"),
        ])

        guard case let .text(message, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(message.contains("not running"))
    }

    // MARK: - Input validation (prevents unrelated-process termination)

    @Test
    func `Empty or whitespace app_name is rejected`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        for empty in ["", "   ", "\t\n"] {
            await #expect(throws: MCPError.self) {
                try await tool.execute(arguments: ["app_name": .string(empty)])
            }
        }
    }

    @Test
    func `Empty or whitespace bundle_id is rejected`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["bundle_id": .string("   ")])
        }
    }

    @Test
    func `Unsafe PIDs that broadcast signals are rejected`() throws {
        // 0 targets the caller's process group; negatives target a process group; 1 is launchd.
        for unsafe in [0, -1, -1000, 1] {
            #expect(throws: MCPError.self) {
                try StopMacAppTool.validatedTargetPID(unsafe)
            }
        }
    }

    @Test
    func `Out-of-range PID is rejected`() throws {
        #expect(throws: MCPError.self) {
            try StopMacAppTool.validatedTargetPID(Int(Int32.max) + 1)
        }
    }

    @Test
    func `Valid PID passes validation unchanged`() throws {
        #expect(try StopMacAppTool.validatedTargetPID(4242) == 4242)
        #expect(try StopMacAppTool.validatedTargetPID(nil) == nil)
    }

    @Test
    func `Unsafe pid argument is rejected at the boundary`() async throws {
        let tool = StopMacAppTool(sessionManager: sessionManager)
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["pid": .int(0)])
        }
        await #expect(throws: MCPError.self) {
            try await tool.execute(arguments: ["pid": .int(-1)])
        }
    }

    // MARK: - Exact app-name matching (no substring / command-line footgun)

    @Test
    func `App-name matching is exact, never substring`() {
        // Exact match on any identifier succeeds.
        #expect(PIDResolver.appNameMatches(
            "MyApp", localizedName: "MyApp", executableName: nil, bundleName: nil))
        #expect(PIDResolver.appNameMatches(
            "MyApp", localizedName: nil, executableName: "MyApp", bundleName: nil))
        #expect(PIDResolver.appNameMatches(
            "MyApp", localizedName: nil, executableName: nil, bundleName: "MyApp"))

        // A name that only appears as a substring (or in another process's arguments) must NOT
        // match — this is the `pkill -f` footgun the fix removes.
        #expect(!PIDResolver.appNameMatches(
            "My", localizedName: "MyApp", executableName: "MyApp", bundleName: "MyApp"))
        #expect(!PIDResolver.appNameMatches(
            "App", localizedName: "MyApp", executableName: "MyApp", bundleName: "MyApp"))
        #expect(!PIDResolver.appNameMatches(
            "MyApp", localizedName: "tail -f /var/log/MyApp.log", executableName: "tail",
            bundleName: nil))
    }

    @Test
    func `Long app names match exactly without truncation`() {
        // pkill's process-name matching truncates to the kernel comm length (~15 chars); exact
        // NSWorkspace matching handles arbitrarily long names.
        let long = "AVeryLongApplicationNameThatExceedsCommLength"
        #expect(PIDResolver.appNameMatches(
            long, localizedName: long, executableName: nil, bundleName: nil))
        #expect(!PIDResolver.appNameMatches(
            "AVeryLongApplic", localizedName: long, executableName: nil, bundleName: nil))
    }
}
