import Testing
@testable import XCMCPCore

/// Covers the run/stop classification and contended-attach detection added for 1wa-p8i
/// (stopped-state desync + misleading attach error).
struct LLDBProcessStateTests {
    @Test
    func `Breakpoint hit parses as stopped`() {
        let output = """
        Process 12345 stopped
        * thread #1, queue = 'com.apple.main-thread', stop reason = breakpoint 1.1
          frame #0: 0x0000000100001f00 MyApp`foo at File.swift:316
        """
        #expect(LLDBSession.parseProcessState(from: output) == .stopped(reason: "breakpoint 1.1"))
    }

    @Test
    func `Resuming parses as running`() {
        #expect(LLDBSession.parseProcessState(from: "Process 12345 resuming") == .running)
    }

    @Test
    func `Stopped without reason parses as stopped`() {
        #expect(LLDBSession.parseProcessState(from: "Process 12345 stopped") == .stopped(reason: nil))
    }

    @Test
    func `Process exit wins over a stale stopped line`() {
        let output = """
        Process 12345 stopped
        Process 12345 exited with status = 0 (0x00000000)
        """
        #expect(LLDBSession.parseProcessState(from: output) == .stopped(reason: "exited"))
    }

    @Test
    func `Neutral output leaves state unchanged`() {
        #expect(LLDBSession.parseProcessState(from: "Current executable set to 'MyApp'.") == nil)
        #expect(LLDBSession.parseProcessState(from: "") == nil)
    }

    @Test
    func `Detects contended attach`() {
        let output = """
        Process 12345 exited with status = -1 (0xffffffff) tried to attach to process already being debugged
        """
        #expect(LLDBSession.outputIndicatesAlreadyDebugged(output))
    }

    @Test
    func `Clean attach is not flagged as contended`() {
        #expect(!LLDBSession.outputIndicatesAlreadyDebugged("Process 12345 stopped"))
    }
}
