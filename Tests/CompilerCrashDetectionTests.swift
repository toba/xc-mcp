import Testing
@testable import XCMCPCore

struct CompilerCrashDetectionTests {
    // MARK: - detectCompilerCrash

    @Test
    func `Detect signal 6 crash`() {
        let output = """
        Building for debugging...
        <unknown>:0: error: compile command failed due to signal 6 (use -v to see invocation)
        """
        #expect(ErrorExtractor.detectCompilerCrash(in: output) == 6)
    }

    @Test
    func `Detect signal 11 crash`() {
        let output = """
        Compiling MyModule File.swift
        <unknown>:0: error: compile command failed due to signal 11 (use -v to see invocation)
        """
        #expect(ErrorExtractor.detectCompilerCrash(in: output) == 11)
    }

    @Test
    func `No crash in clean build`() {
        let output = """
        Building for debugging...
        Build complete!
        """
        #expect(ErrorExtractor.detectCompilerCrash(in: output) == nil)
    }

    @Test
    func `No crash in normal error output`() {
        let output = """
        main.swift:15:5: error: use of undeclared identifier 'foo'
        """
        #expect(ErrorExtractor.detectCompilerCrash(in: output) == nil)
    }

    // MARK: - extractCrashDetails

    @Test
    func `Extract crash details with single file`() {
        let verboseOutput = """
        /usr/bin/swiftc -module-name MyModule -o /tmp/out.o /path/to/CrashingFile.swift
        <unknown>:0: error: compile command failed due to signal 6 (use -v to see invocation)
        """
        let details = ErrorExtractor.extractCrashDetails(from: verboseOutput, signal: 6)

        #expect(details.contains("signal 6"))
        #expect(details.contains("CrashingFile.swift"))
        #expect(details.contains("Crashing file:"))
    }

    @Test
    func `Extract crash details with multiple files`() {
        let verboseOutput = """
        /usr/bin/swiftc -module-name Mod -o /tmp/out.o /src/A.swift /src/B.swift /src/C.swift
        <unknown>:0: error: compile command failed due to signal 11 (use -v to see invocation)
        """
        let details = ErrorExtractor.extractCrashDetails(from: verboseOutput, signal: 11)

        #expect(details.contains("signal 11"))
        #expect(details.contains("A.swift"))
        #expect(details.contains("B.swift"))
        #expect(details.contains("C.swift"))
        #expect(details.contains("Crashing compilation unit"))
    }

    @Test
    func `Extract crash details with swift-frontend`() {
        let verboseOutput = """
        /usr/bin/swift-frontend -frontend -c -primary-file /src/Broken.swift -o /tmp/out.o
        <unknown>:0: error: compile command failed due to signal 6 (use -v to see invocation)
        """
        let details = ErrorExtractor.extractCrashDetails(from: verboseOutput, signal: 6)

        #expect(details.contains("Broken.swift"))
        #expect(details.contains("Compiler invocation:"))
    }

    @Test
    func `Extract crash details with stack trace`() {
        let verboseOutput = """
        /usr/bin/swiftc -module-name Mod /src/File.swift
        Stack dump:
        0  swift-frontend  0x000000010a5b1234 llvm::sys::PrintStackTrace
        1  swift-frontend  0x000000010a5b5678 swift::ASTContext::getIdentifier
        <unknown>:0: error: compile command failed due to signal 11 (use -v to see invocation)
        """
        let details = ErrorExtractor.extractCrashDetails(from: verboseOutput, signal: 11)

        #expect(details.contains("Compiler backtrace:"))
        #expect(details.contains("Stack dump:"))
    }

    @Test
    func `Extract crash details without compiler invocation`() {
        let verboseOutput = """
        <unknown>:0: error: compile command failed due to signal 6 (use -v to see invocation)
        """
        let details = ErrorExtractor.extractCrashDetails(from: verboseOutput, signal: 6)

        // Should still produce the header even without invocation details
        #expect(details.contains("signal 6"))
        #expect(!details.contains("Crashing file:"))
        #expect(!details.contains("Compiler invocation:"))
    }
}
