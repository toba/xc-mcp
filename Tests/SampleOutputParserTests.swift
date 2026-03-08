import Testing
@testable import XCMCPCore

struct SampleOutputParserTests {
    // MARK: - Section splitting

    static let sampleOutput = """
    Analysis of sampling Thesis (pid 12345) every 1 millisecond
    Process:         Thesis [12345]
    Path:            /Users/test/Build/Thesis.app/Contents/MacOS/Thesis
    Identifier:      com.toba.thesis
    Code Type:       ARM64E
    Platform:        macOS
    ----

    Call graph:
        1000 Thread_100   DispatchQueue_1: com.apple.main-thread  (serial)
          + 1000 start  (in dyld) + 6076  [0x195256b98]
          +   1000 main  (in Thesis) + 100  [0x100000100]
          +     700 SQLMigration.runSchemas  (in Thesis) + 44  [0x100001000]
          +       500 SQLCreator.createTrigger  (in Thesis) + 103  [0x100002000]
          +       200 NodeSchema.validate  (in Thesis) + 50  [0x100003000]
          +     200 AppDelegate.didFinishLaunching  (in Thesis) + 80  [0x100004000]
          +       200 NSApplicationMain  (in AppKit) + 880  [0x1995cb2dc]
          +         200 -[NSApplication run]  (in AppKit) + 480  [0x1995f4be4]
          +           200 CFRunLoopRunSpecific  (in CoreFoundation) + 572  [0x1956e09e8]
          +             200 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x1955b5c34]
          +     100 CloudKitSchema.createTriggers  (in Thesis) + 51  [0x100005000]
          +       100 SQLCreator.createTrigger  (in Thesis) + 103  [0x100002000]
        500 Thread_200: com.apple.NSEventThread
          + 500 thread_start  (in libsystem_pthread.dylib) + 8  [0x1955f2b80]
          +   500 _pthread_start  (in libsystem_pthread.dylib) + 136  [0x1955f7bc8]
          +     500 _NSEventThread  (in AppKit) + 140  [0x19972578c]
          +       500 mach_msg2_trap  (in libsystem_kernel.dylib) + 8  [0x1955b5c34]
        300 Thread_300
          + 300 start_wqthread  (in libsystem_pthread.dylib) + 8  [0x1955f2b74]
          +   300 _pthread_wqthread  (in libsystem_pthread.dylib) + 368  [0x1955f3e6c]
          +     300 __workq_kernreturn  (in libsystem_kernel.dylib) + 8  [0x1955b78b0]

    Total number in stack (recursive counted multiple, when >=5):

    Sort by top of stack, same collapsed (when >= 5):
            mach_msg2_trap  (in libsystem_kernel.dylib)        700
            __workq_kernreturn  (in libsystem_kernel.dylib)        300

    Binary Images:
           0x100000000 -        0x100100000 +Thesis (1.0) <ABC123> /Users/test/Build/Thesis.app/Contents/MacOS/Thesis
    """

    @Test
    func `Splits sections correctly`() {
        let sections = SampleOutputParser.splitSections(Self.sampleOutput)

        #expect(sections.header.contains("Process:"))
        #expect(sections.header.contains("Thesis"))
        #expect(sections.callGraph.contains("Call graph:"))
        #expect(sections.callGraph.contains("SQLMigration"))
        #expect(sections.binaryImages.contains("Binary Images:"))
    }

    @Test
    func `Extracts app binary name from header`() {
        let sections = SampleOutputParser.splitSections(Self.sampleOutput)
        let appBinary = SampleOutputParser.extractAppBinary(
            from: sections.binaryImages, header: sections.header,
        )
        #expect(appBinary == "Thesis")
    }

    // MARK: - Call graph parsing

    @Test
    func `Parses threads from call graph`() {
        let sections = SampleOutputParser.splitSections(Self.sampleOutput)
        let threads = SampleOutputParser.parseCallGraph(sections.callGraph)

        #expect(threads.count == 3)
        #expect(threads[0].isMainThread)
        #expect(threads[0].totalSamples == 1000)
        #expect(threads[1].name.contains("NSEventThread"))
        #expect(threads[1].totalSamples == 500)
        #expect(threads[2].totalSamples == 300)
    }

    @Test
    func `Identifies idle threads`() {
        let sections = SampleOutputParser.splitSections(Self.sampleOutput)
        let threads = SampleOutputParser.parseCallGraph(sections.callGraph)

        // Thread_200 (NSEventThread) ends at mach_msg2_trap — idle
        #expect(SampleOutputParser.isThreadIdle(threads[1]))
        // Thread_300 ends at __workq_kernreturn — idle
        #expect(SampleOutputParser.isThreadIdle(threads[2]))
    }

    // MARK: - Frame line parsing

    @Test
    func `Parses standard frame line`() {
        let line = "    +   700 SQLMigration.runSchemas  (in Thesis) + 44  [0x100001000]"
        let parsed = SampleOutputParser.parseFrameLine(line)

        #expect(parsed != nil)
        #expect(parsed?.function == "SQLMigration.runSchemas")
        #expect(parsed?.library == "Thesis")
        #expect(parsed?.samples == 700)
    }

    @Test
    func `Parses ObjC frame line`() {
        let line =
            "    +       200 -[NSApplication run]  (in AppKit) + 480  [0x1995f4be4]"
        let parsed = SampleOutputParser.parseFrameLine(line)

        #expect(parsed != nil)
        #expect(parsed?.function == "-[NSApplication run]")
        #expect(parsed?.library == "AppKit")
        #expect(parsed?.samples == 200)
    }

    // MARK: - Idle function detection

    @Test
    func `Identifies idle functions`() {
        #expect(SampleOutputParser.isIdleFunction("mach_msg2_trap"))
        #expect(SampleOutputParser.isIdleFunction("__workq_kernreturn"))
        #expect(SampleOutputParser.isIdleFunction("__psynch_cvwait"))
        #expect(!SampleOutputParser.isIdleFunction("SQLMigration.runSchemas"))
    }

    // MARK: - System library detection

    @Test
    func `Identifies system libraries`() {
        #expect(SampleOutputParser.isSystemLibrary("libsystem_kernel.dylib"))
        #expect(SampleOutputParser.isSystemLibrary("AppKit"))
        #expect(SampleOutputParser.isSystemLibrary("CoreFoundation"))
        #expect(SampleOutputParser.isSystemLibrary("libdispatch.dylib"))
        #expect(!SampleOutputParser.isSystemLibrary("Thesis"))
        #expect(!SampleOutputParser.isSystemLibrary("MyFramework"))
    }

    // MARK: - Full summarize

    @Test
    func `Summarize with app filter shows only app functions`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "app",
            topN: 20,
            thread: "main",
        )

        #expect(summary.contains("SQLMigration.runSchemas"))
        #expect(summary.contains("SQLCreator.createTrigger"))
        #expect(summary.contains("Thesis"))
        // Should not include system-only idle functions as heaviest
        #expect(!summary.contains("mach_msg2_trap"))
    }

    @Test
    func `Summarize shows thread summary`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "app",
            topN: 20,
            thread: "main",
        )

        #expect(summary.contains("Thread Summary"))
        #expect(summary.contains("1000 samples"))
    }

    @Test
    func `Summarize with all threads shows all`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "app",
            topN: 20,
            thread: "all",
        )

        #expect(summary.contains("Thread Summary"))
        // Should mention all three threads
        #expect(summary.contains("Thread_100"))
    }

    @Test
    func `Summarize with unknown thread returns hint`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "app",
            topN: 20,
            thread: "nonexistent",
        )

        #expect(summary.contains("No matching threads"))
        #expect(summary.contains("Available threads"))
    }

    @Test
    func `Summarize with all filter includes system frames`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "all",
            topN: 20,
            thread: "main",
        )

        // Should include app AND system functions (but still filter idle)
        #expect(summary.contains("SQLMigration.runSchemas"))
    }

    @Test
    func `Summarize shows heaviest call paths`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "app",
            topN: 20,
            thread: "main",
        )

        #expect(summary.contains("Heaviest Call Paths"))
        #expect(summary.contains("→"))
    }

    @Test
    func `topN limits output`() {
        let summary = SampleOutputParser.summarize(
            rawOutput: Self.sampleOutput,
            filter: "all",
            topN: 1,
            thread: "main",
        )

        // With topN=1, should only have one entry in function table
        // Count lines in the Heaviest Functions section
        let lines = summary.components(separatedBy: .newlines)
        let functionTableLines = lines.filter { $0.contains("|") && !$0.contains("---") }
        // Header + 1 data row
        #expect(functionTableLines.count <= 2)
    }
}
