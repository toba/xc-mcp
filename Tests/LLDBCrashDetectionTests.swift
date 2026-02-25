import Testing
@testable import XCMCPCore

@Suite("LLDB Crash Detection")
struct LLDBCrashDetectionTests {
    @Test("Detects SIGABRT crash")
    func sigabrt() {
        let output = """
        Process 12345 stopped
        * thread #1, queue = 'com.apple.main-thread', stop reason = signal SIGABRT
          frame #0: 0x00007fff abort
        """
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects SIGSEGV crash")
    func sigsegv() {
        let output = "stop reason = signal SIGSEGV"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects EXC_BAD_ACCESS")
    func excBadAccess() {
        let output = "stop reason = EXC_BAD_ACCESS (code=1, address=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects EXC_BAD_INSTRUCTION")
    func excBadInstruction() {
        let output = "stop reason = EXC_BAD_INSTRUCTION (code=EXC_I386_INVOP, subcode=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects EXC_CRASH")
    func excCrash() {
        let output = "stop reason = EXC_CRASH (code=0, subcode=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects process exit with status")
    func exitWithStatus() {
        let output = "Process 12345 exited with status = 1 (0x00000001)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Detects process exit with signal")
    func exitWithSignal() {
        let output = "Process 12345 exited with signal = 11"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Ignores library load noise")
    func libraryLoadNoise() {
        let output = """
        2 locations added to breakpoint 1
        Process 12345 resuming
        """
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Ignores attach noise")
    func attachNoise() {
        let output = """
        Executable module set to "/Applications/MyApp.app/Contents/MacOS/MyApp".
        Architecture set to: arm64-apple-macosx-.
        """
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Ignores benign stop reason (breakpoint)")
    func breakpointStop() {
        let output = "stop reason = breakpoint 1.1"
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test("Ignores empty output")
    func emptyOutput() {
        #expect(!LLDBSession.outputIndicatesCrash(""))
    }
}
