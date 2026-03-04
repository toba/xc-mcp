import Testing
@testable import XCMCPCore

struct LLDBCrashDetectionTests {
    @Test
    func `Detects SIGABRT crash`() {
        let output = """
        Process 12345 stopped
        * thread #1, queue = 'com.apple.main-thread', stop reason = signal SIGABRT
          frame #0: 0x00007fff abort
        """
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects SIGSEGV crash`() {
        let output = "stop reason = signal SIGSEGV"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects EXC_BAD_ACCESS`() {
        let output = "stop reason = EXC_BAD_ACCESS (code=1, address=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects EXC_BAD_INSTRUCTION`() {
        let output = "stop reason = EXC_BAD_INSTRUCTION (code=EXC_I386_INVOP, subcode=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects EXC_CRASH`() {
        let output = "stop reason = EXC_CRASH (code=0, subcode=0x0)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects process exit with status`() {
        let output = "Process 12345 exited with status = 1 (0x00000001)"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Detects process exit with signal`() {
        let output = "Process 12345 exited with signal = 11"
        #expect(LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Ignores library load noise`() {
        let output = """
        2 locations added to breakpoint 1
        Process 12345 resuming
        """
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Ignores attach noise`() {
        let output = """
        Executable module set to "/Applications/MyApp.app/Contents/MacOS/MyApp".
        Architecture set to: arm64-apple-macosx-.
        """
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Ignores benign stop reason (breakpoint)`() {
        let output = "stop reason = breakpoint 1.1"
        #expect(!LLDBSession.outputIndicatesCrash(output))
    }

    @Test
    func `Ignores empty output`() {
        #expect(!LLDBSession.outputIndicatesCrash(""))
    }
}
