import Testing
@testable import XCMCPCore

/// A build command that fails with no diagnostic of its own, such as a CodeSign failure.
struct CommandFailureTests {
    private static let codeSignTask = """
        CodeSign /DD/App.app/PlugIns/Stickers.appex (in target 'Stickers' from project 'App')
            cd /src/App
            /usr/bin/codesign --force --sign ABC /DD/App.app/PlugIns/Stickers.appex
        /DD/App.app/PlugIns/Stickers.appex: errSecInternalComponent
        Command CodeSign failed with a nonzero exit code
        """

    private static let codeSignMessage =
        "/DD/App.app/PlugIns/Stickers.appex: errSecInternalComponent "
        + "Command CodeSign failed with a nonzero exit code"

    @Test func `A CodeSign failure in an archive is an error with its reason`() {
        let result = BuildOutputParser().parse(
            input: Self.codeSignTask + """

                ** ARCHIVE FAILED **
                """)

        #expect(result.status == "failed")
        #expect(result.errors.map(\.message) == [Self.codeSignMessage])
    }

    @Test func `A CodeSign failure after CLEAN SUCCEEDED in clean test is reported once`() {
        let result = BuildOutputParser().parse(
            input: "** CLEAN SUCCEEDED **\n\n"
                + Self.codeSignTask + """

                    Testing failed:
                    \tCommand CodeSign failed with a nonzero exit code
                    \tTesting cancelled because the build failed.

                    ** TEST FAILED **
                    """)

        #expect(result.status == "failed")
        #expect(result.errors.map(\.message) == [Self.codeSignMessage])
    }

    @Test func `A CodeSign failure in a log cut off after CLEAN SUCCEEDED fails the run`() {
        let result = BuildOutputParser().parse(
            input: "** CLEAN SUCCEEDED **\n\n" + Self.codeSignTask,
        )

        #expect(result.status == "failed")
        #expect(result.summary.errors == 1)
    }

    @Test func `A failed compiler is not restated`() {
        let result = BuildOutputParser().parse(
            input: """
                SwiftCompile normal arm64 /src/A.swift (in target 'App' from project 'App')
                    cd /src
                /src/A.swift:3:5: error: cannot find 'x' in scope
                Command SwiftCompile failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(result.errors.map(\.message) == ["cannot find 'x' in scope"])
    }

    @Test func `A failed link is explained by its linker errors`() {
        let result = BuildOutputParser().parse(
            input: """
                Ld /DD/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
                    cd /src
                Undefined symbols for architecture arm64:
                  "_foo", referenced from:
                      _main in main.o
                ld: symbol(s) not found for architecture arm64
                Command Ld failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(!result.errors.contains { $0.message.contains("Command Ld failed") })
        #expect(result.summary.linkerErrors > 0)
    }

    @Test func `A script failure does not hide a CodeSign failure in another target`() {
        let result = BuildOutputParser().parse(
            input: """
                PhaseScriptExecution Lint /DD/Script.sh (in target 'App' from project 'App')
                    cd /src
                lint found 3 problems
                Command PhaseScriptExecution failed with a nonzero exit code
                """ + "\n" + Self.codeSignTask + """

                    ** BUILD FAILED **
                    """)

        #expect(result.summary.errors == 2)
        #expect(result.errors.contains { $0.message == Self.codeSignMessage })
    }

    @Test func `A script failure restated under Testing failed is reported once`() {
        let result = BuildOutputParser().parse(
            input: """
                PhaseScriptExecution Lint /DD/Script.sh (in target 'App' from project 'App')
                    cd /src
                lint found 3 problems
                Command PhaseScriptExecution failed with a nonzero exit code

                Testing failed:
                \tCommand PhaseScriptExecution failed with a nonzero exit code
                \tTesting cancelled because the build failed.

                ** TEST FAILED **
                """)

        #expect(result.summary.errors == 1)
    }

    @Test func `A failure listed only under Testing failed is kept`() {
        let result = BuildOutputParser().parse(
            input: """
                Testing failed:
                \tCommand CodeSign failed with a nonzero exit code
                \tTesting cancelled because the build failed.

                ** TEST FAILED **
                """)

        #expect(
            result.errors.map(\.message) == ["Command CodeSign failed with a nonzero exit code"])
    }

    @Test func `A failure that a later success marker vouches for is not an error`() {
        let result = BuildOutputParser().parse(
            input: Self.codeSignTask + """

                ** BUILD SUCCEEDED **
                """)

        #expect(result.status == "success")
        #expect(result.summary.errors == 0)
    }

    @Test func `A rule name of several capitalised words is recognised`() {
        let result = BuildOutputParser().parse(
            input: """
                SwiftDriver\\ Compilation\\ Requirements App normal arm64 (in target 'App' from project 'App')
                    cd /src
                Command SwiftDriver Compilation Requirements failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(
            result.errors.map(
                \.message) == [
                    "Command SwiftDriver Compilation Requirements failed with a nonzero exit code"
                ])
    }

    @Test func `Prose that reads like a failed command is not one`() {
        let result = BuildOutputParser().parse(
            input: """
                Command line invocation failed with a nonzero exit code

                ** BUILD SUCCEEDED **
                """)

        #expect(result.summary.errors == 0)
    }

    @Test func `The reason skips blank lines and stops at an earlier failure`() {
        let result = BuildOutputParser().parse(
            input: """
                CodeSign /DD/A.app (in target 'A' from project 'App')
                    /usr/bin/codesign --sign ABC /DD/A.app
                /DD/A.app: first reason
                Command CodeSign failed with a nonzero exit code
                Validate /DD/B.app (in target 'B' from project 'App')
                b.app: second reason

                Command ValidateEmbeddedBinary failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(
            result.errors.map(
                \.message) == [
                    "/DD/A.app: first reason Command CodeSign failed with a nonzero exit code",
                    "b.app: second reason Command ValidateEmbeddedBinary failed with a nonzero exit code",
                ])
    }

    @Test func `A task indented under the transcript reads the reason at its own depth`() {
        let result = BuildOutputParser().parse(
            input: """
                CodeSign /DD/A.app (in target 'A' from project 'App')
                        /usr/bin/codesign --sign ABC /DD/A.app
                    /DD/A.app: errSecInternalComponent
                    Command CodeSign failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(
            result.errors.map(
                \.message) == [
                    "/DD/A.app: errSecInternalComponent Command CodeSign failed with a nonzero exit code"
                ])
    }

    @Test func `Two tasks that fail alike are two errors`() {
        let result = BuildOutputParser().parse(
            input: """
                CodeSign /DD/A.app (in target 'A' from project 'App')
                Command CodeSign failed with a nonzero exit code
                CodeSign /DD/B.app (in target 'B' from project 'App')
                Command CodeSign failed with a nonzero exit code

                ** BUILD FAILED **
                """)

        #expect(result.summary.errors == 2)
    }
}
