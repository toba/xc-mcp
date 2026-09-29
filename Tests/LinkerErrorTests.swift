import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

struct LinkerErrorTests {
    @Test
    func `Parse undefined symbol linker error`() throws {
        let parser = BuildOutputParser()

        let input = try String(
            contentsOf: TestFixtures.url("linker-error-output.txt"), encoding: .utf8,
        )

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

    @Test
    func `Stamp the Ld target on a duplicate symbol`() throws {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Release/GoogleDocs.app/Contents/MacOS/GoogleDocs normal (in target 'GoogleDocs' from project 'Thesis')
                cd /Users/dev/Thesis
                /Applications/Xcode.app/Contents/Developer/usr/bin/clang -o GoogleDocs
            duplicate symbol '_relinkableLibraryClasses' in:
                /Build/Products/Release/DOM.framework/Versions/A/DOM
                bundle-file
            ld: 1 duplicate symbol
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        let error = try #require(result.linkerErrors.first)
        #expect(error.kind == .duplicateSymbol)
        #expect(error.target == "GoogleDocs")

        let formatted = BuildResultFormatter.formatBuildResult(result)
        #expect(formatted.contains("(in target 'GoogleDocs')"))
    }

    @Test
    func `Stamp the Ld target on an undefined symbol and a missing framework`() {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
                cd /Users/dev/App
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            ld: framework not found SomeFramework
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.count == 2)
        #expect(result.linkerErrors.allSatisfy { $0.target == "App" })
    }

    @Test
    func `A later task header clears the link target`() throws {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
                cd /Users/dev/App
            CompileSwift normal arm64 /Users/dev/App/Other.swift (in target 'Other' from project 'App')
                cd /Users/dev/App
            ld: library not found for -lSomeLib
            """

        let result = parser.parse(input: input)

        let error = try #require(result.linkerErrors.first)
        #expect(error.target == nil)
        #expect(!BuildResultFormatter.formatBuildResult(result).contains("(in target"))
    }

    @Test
    func `Same missing symbol in two targets stays two errors`() {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/A.app/Contents/MacOS/A normal (in target 'A' from project 'P')
            Undefined symbols for architecture arm64:
              "_Missing", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            Ld /Build/Products/Debug/B.app/Contents/MacOS/B normal (in target 'B' from project 'P')
            Undefined symbols for architecture arm64:
              "_Missing", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.map(\.target) == ["A", "B"])
    }

    @Test
    func `A duplicate symbol cut off before the summary keeps its own target`() throws {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/A.app/Contents/MacOS/A normal (in target 'A' from project 'P')
            duplicate symbol '_shared' in:
                /path/A.o
                /path/B.o
            Ld /Build/Products/Debug/B.app/Contents/MacOS/B normal (in target 'B' from project 'P')
                cd /Users/dev/P
                /Applications/Xcode.app/Contents/Developer/usr/bin/clang -o B
            """

        let result = parser.parse(input: input)

        let error = try #require(result.linkerErrors.first)
        #expect(result.linkerErrors.count == 1)
        #expect(error.target == "A")
        #expect(error.conflictingFiles == ["/path/A.o", "/path/B.o"])
    }

    @Test
    func `An indented Ld line in the failed-commands list sets no target`() throws {
        let parser = BuildOutputParser()
        let input = """
            The following build commands failed:
            \tLd /Build/Products/Debug/B.app/Contents/MacOS/B normal (in target 'B' from project 'P')
            ld: library not found for -lBar
            """

        let result = parser.parse(input: input)

        let error = try #require(result.linkerErrors.first)
        #expect(error.target == nil)
    }

    @Test
    func `The same missing symbol twice under one Ld is one error`() {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/A.app/Contents/MacOS/A normal (in target 'A' from project 'P')
            Undefined symbols for architecture arm64:
              "_Missing", referenced from:
                  main.main() -> () in main.o
              "_Missing", referenced from:
                  main.main() -> () in main.o
            ld: symbol(s) not found for architecture arm64
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.count == 1)
        #expect(result.linkerErrors.first?.target == "A")
    }

    @Test
    func `The Ld line still records the Link phase`() throws {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
            ld: framework not found SomeFramework
            """

        let result = parser.parse(input: input, parseBuildInfo: true)

        let target = try #require(result.buildInfo?.targets.first { $0.name == "App" })
        #expect(target.phases.contains("Link"))
        #expect(result.linkerErrors.first?.target == "App")
    }

    @Test
    func `A second parse starts with no link target`() throws {
        let parser = BuildOutputParser()
        _ = parser.parse(input: """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
            ld: framework not found SomeFramework
            """)

        let result = parser.parse(input: "ld: framework not found OtherFramework")

        let error = try #require(result.linkerErrors.first)
        #expect(error.target == nil)
    }

    @Test
    func `Format a non-symbol linker error with its target`() {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
            ld: framework not found SomeFramework
            """

        let formatted = BuildResultFormatter.formatBuildResult(parser.parse(input: input))

        #expect(formatted.contains("  framework not found SomeFramework (in target 'App')"))
    }

    @Test
    func `Parse the ld-prime framework and library not found forms`() {
        let parser = BuildOutputParser()
        let input = """
            Ld /Build/Products/Debug/App.app/Contents/MacOS/App normal (in target 'App' from project 'App')
            ld: framework 'SomeFramework' not found
            ld: library 'SomeLib' not found
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let result = parser.parse(input: input)

        #expect(result.linkerErrors.map(\.message) == [
            "framework not found SomeFramework", "library not found for -lSomeLib",
        ])
        #expect(result.linkerErrors.allSatisfy { $0.target == "App" })
    }
}
