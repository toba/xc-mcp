import Testing
@testable import XCMCPCore

/// Tests for the auto-continuing backtrace-capture breakpoint command builder (issue dq5-oel).
struct CaptureBacktraceCommandTests {
    @Test
    func `builds an auto-continuing breakpoint with bounded bt and a sentinel marker`() {
        let cmd = LLDBRunner.captureBreakpointCommand(
            symbol: "sqlite3_prepare_v2", condition: nil, frameCount: 12,
        )
        #expect(cmd.contains("breakpoint set --name \"sqlite3_prepare_v2\""))
        #expect(cmd.contains("--auto-continue true"))
        #expect(cmd.contains("--command \"bt 12\""))
        #expect(cmd.contains(LLDBRunner.captureMarker))
        #expect(!cmd.contains("--condition"))
    }

    @Test
    func `includes the condition and a full backtrace when frame count is omitted`() {
        let cmd = LLDBRunner.captureBreakpointCommand(
            symbol: "myFunc", condition: "$arg1 == 42", frameCount: nil,
        )
        #expect(cmd.contains("--condition '$arg1 == 42'"))
        #expect(cmd.contains("--command \"bt\""))
        #expect(!cmd.contains("bt 0"))
    }
}

/// Tests for the breakpoint condition advisor that warns about pathological breakpoints which can
/// wedge a debug session (issue dq5-oel).
struct BreakpointConditionAdvisorTests {
    @Test
    func `warns about a high-frequency symbol`() {
        let warnings = BreakpointConditionAdvisor.warnings(
            for: "breakpoint set -n sqlite3_prepare_v2",
        )
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("sqlite3_prepare_v2"))
        #expect(warnings[0].contains("high-frequency"))
    }

    @Test
    func `warns about both hot symbol and inferior-calling condition`() {
        let cmd =
            "breakpoint set -n sqlite3_prepare_v2 -n sqlite3_prepare_v3 -c '(int)strncmp((char*)$arg2, \"DELETE\", 6) == 0 && (BOOL)strstr((char*)$arg2, \"node\") != 0'"
        let warnings = BreakpointConditionAdvisor.warnings(for: cmd)
        #expect(warnings.count == 2)
        #expect(warnings.contains { $0.contains("high-frequency") })
        #expect(warnings.contains { $0.contains("strncmp") && $0.contains("expression evaluator") })
    }

    @Test
    func `warns about inferior call even on a benign symbol`() {
        let warnings = BreakpointConditionAdvisor.warnings(
            for: "breakpoint set --name myFunction --condition 'strcmp(x, \"y\") == 0'",
        )
        #expect(warnings.count == 1)
        #expect(warnings[0].contains("strcmp"))
    }

    @Test
    func `no warning for a register-only condition on a benign symbol`() {
        let warnings = BreakpointConditionAdvisor.warnings(
            for: "breakpoint set --name myFunction --condition '$arg1 == 42'",
        )
        #expect(warnings.isEmpty)
    }

    @Test
    func `ignores non-breakpoint commands`() {
        #expect(BreakpointConditionAdvisor.warnings(for: "thread backtrace").isEmpty)
        #expect(BreakpointConditionAdvisor.warnings(for: "po strncmp(a, b, 1)").isEmpty)
        #expect(BreakpointConditionAdvisor.warnings(for: "process status").isEmpty)
    }

    @Test
    func `extracts quoted and unquoted conditions`() {
        #expect(
            BreakpointConditionAdvisor.extractCondition(from: "breakpoint set -n f -c 'a == b'")
                == "a == b",
        )
        #expect(
            BreakpointConditionAdvisor.extractCondition(
                from: "breakpoint set -n f --condition \"x > 0\"",
            ) == "x > 0",
        )
        #expect(
            BreakpointConditionAdvisor.extractCondition(from: "breakpoint set -n f") == nil,
        )
    }
}
