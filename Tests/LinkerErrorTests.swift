import Testing
import Foundation
@testable import XCMCPCore

struct LinkerErrorTests {
    @Test
    func `Parse undefined symbol linker error`() throws {
        let parser = BuildOutputParser()

        let fixtureURL = try #require(Bundle.module.url(
            forResource: "linker-error-output", withExtension: "txt", subdirectory: "Fixtures",
        ),
        )
        let input = try String(contentsOf: fixtureURL, encoding: .utf8)

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count >= 1)
    }

    @Test
    func `Parse inline linker error`() {
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

    @Test
    func `Parse framework not found linker error`() {
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

    @Test
    func `Parse library not found linker error`() {
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

    @Test
    func `Parse duplicate symbol with framework and bundle-file paths`() {
        let parser = BuildOutputParser()
        // Real ld output shape from the fm2-cax report: the defining files are a framework binary
        // and the literal `bundle-file`, neither of which ends in .o/.a.
        let input = """
            duplicate symbol '_relinkableLibraryClasses' in:
                /Build/Products/Release/DOM.framework/Versions/A/DOM
                bundle-file
            ld: 2 duplicate symbols
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        #expect(result.status == "failed")
        #expect(result.linkerErrors.count == 1)
        let error = result.linkerErrors[0]
        #expect(error.kind == .duplicateSymbol)
        #expect(error.symbol == "_relinkableLibraryClasses")
        #expect(
            error.conflictingFiles == [
                "/Build/Products/Release/DOM.framework/Versions/A/DOM",
                "bundle-file",
            ])

        // The formatter must label it as a duplicate, not invert it to "Undefined symbol".
        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("Duplicate symbol '_relinkableLibraryClasses'"))
        #expect(!formatted.contains("Undefined symbol '_relinkableLibraryClasses'"))
        #expect(formatted.contains("bundle-file"))
    }

    @Test
    func `Parse multiple duplicate symbols`() {
        let parser = BuildOutputParser()
        let input = """
            duplicate symbol '_symbolA' in:
                /path/one/A.framework/Versions/A/A
                /path/two/libB.a
            duplicate symbol '_symbolB' in:
                /path/one/A.framework/Versions/A/A
                /path/two/libB.a
            ld: 2 duplicate symbols
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.count == 2)
        #expect(result.linkerErrors.allSatisfy { $0.kind == .duplicateSymbol })
        #expect(Set(result.linkerErrors.map(\.symbol)) == ["_symbolA", "_symbolB"])
    }

    @Test
    func `Undefined and duplicate symbols with same name stay distinct`() {
        let parser = BuildOutputParser()
        let input = """
            Undefined symbols for architecture arm64:
              "_shared", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            duplicate symbol '_shared' in:
                /path/A.o
                /path/B.o
            ld: 1 duplicate symbol
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.count == 2)
        #expect(result.linkerErrors.contains {
            $0.kind == .undefinedSymbol && $0.symbol == "_shared"
        })
        #expect(result.linkerErrors.contains {
            $0.kind == .duplicateSymbol && $0.symbol == "_shared"
        })
    }

    @Test
    func `Deduplicate linker errors`() {
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
