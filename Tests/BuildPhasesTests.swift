import Testing

@testable import XCMCPCore

@Suite("Build Phases Tests")
struct BuildPhasesTests {
    @Test("PhaseScriptExecution failure basic")
    func testPhaseScriptExecutionFailureBasic() {
        let parser = BuildOutputParser()
        let output = """
            /bin/sh -c /Users/test/DerivedData/Build/Script.sh
            The path lib/main.dart does not exist
            The path  does not exist
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        #expect(result.summary.errors == 1)
        #expect(!result.errors.isEmpty)
        #expect(result.errors[0].file == nil)
        #expect(result.errors[0].line == nil)
        #expect(result.errors[0].message.contains("Command PhaseScriptExecution failed"))
        #expect(result.errors[0].message.contains("The path lib/main.dart does not exist"))
    }

    @Test("PhaseScriptExecution with multiple errors")
    func testPhaseScriptExecutionWithMultipleErrors() {
        let parser = BuildOutputParser()
        let output = """
            Build started...

            Compiling Swift files...
            file.swift:10: error: Cannot find 'someFunction' in scope

            Running post-build script...
            /bin/sh -c /path/to/script.sh
            Script execution failed
            Command PhaseScriptExecution failed with a nonzero exit code

            Build complete!
            """

        let result = parser.parse(input: output)

        #expect(result.summary.errors == 2)
    }

    @Test("PhaseScriptExecution with no context")
    func testPhaseScriptExecutionWithNoContext() {
        let parser = BuildOutputParser()
        let output = """
            Command PhaseScriptExecution failed with a nonzero exit code
            """

        let result = parser.parse(input: output)

        #expect(result.summary.errors == 1)
        #expect(result.errors[0].message.contains("Command PhaseScriptExecution failed"))
    }

    @Test("Build succeeded does not create phase error")
    func testBuildSucceededDoesNotCreatePhaseError() {
        let parser = BuildOutputParser()
        let output = """
            Running phase script...
            Build succeeded in 5.234 seconds
            """

        let result = parser.parse(input: output)
        #expect(result.summary.errors == 0)
    }
}
