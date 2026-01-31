import Foundation
import Testing

@testable import XCMCPCore

@Suite("Linker Error Tests")
struct LinkerErrorTests {
    @Test("Parse undefined symbol linker error")
    func testParseLinkerError() throws {
        let parser = BuildOutputParser()

        let fixtureURL = Bundle.module.url(
            forResource: "linker-error-output", withExtension: "txt", subdirectory: "Fixtures")!
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count >= 1)
    }

    @Test("Parse inline linker error")
    func testParseInlineLinkerError() {
        let parser = BuildOutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count == 1)
        #expect(result.linkerErrors[0].symbol == "_MissingSymbol")
        #expect(result.linkerErrors[0].architecture == "arm64")
        #expect(result.linkerErrors[0].referencedFrom == "main.o")
    }

    @Test("Parse framework not found linker error")
    func testFrameworkNotFound() {
        let parser = BuildOutputParser()
        let input = """
            ld: framework not found SomeFramework
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count == 1)
        #expect(result.linkerErrors[0].message == "framework not found SomeFramework")
    }

    @Test("Parse library not found linker error")
    func testLibraryNotFound() {
        let parser = BuildOutputParser()
        let input = """
            ld: library not found for -lSomeLib
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count == 1)
        #expect(result.linkerErrors[0].message == "library not found for -lSomeLib")
    }

    @Test("Deduplicate linker errors")
    func testDeduplicateLinkerErrors() {
        let parser = BuildOutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  ViewController.o in main.o
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  ViewController.o in main.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        #expect(result.summary.linkerErrors == 1)
        #expect(result.linkerErrors.count == 1)
    }
}
