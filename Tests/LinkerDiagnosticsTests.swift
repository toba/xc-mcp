import Testing
import Foundation
@testable import XCMCPCore

struct LinkerDiagnosticsTests {
    @Test
    func `Extracts duplicate-symbol block verbatim with every colliding file`() {
        let raw = """
            Ld /DerivedData/Thesis.app/Contents/MacOS/Thesis normal (in target 'Thesis' from project 'Thesis')
                cd /Users/jason/Thesis
                /usr/bin/clang -Xlinker -reproducible ...
            duplicate symbol '_relinkableLibraryClasses' in:
                /DerivedData/Build/Products/Release/FrameworkA.framework/Versions/A/FrameworkA
                /DerivedData/Build/Products/Release/FrameworkB.framework/Versions/A/FrameworkB
            ld: 1 duplicate symbol for architecture arm64
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let extracted = LinkerDiagnostics.extract(from: raw)

        #expect(extracted.contains("duplicate symbol '_relinkableLibraryClasses' in:"))
        #expect(extracted.contains("FrameworkA.framework/Versions/A/FrameworkA"))
        #expect(extracted.contains("FrameworkB.framework/Versions/A/FrameworkB"))
        #expect(extracted.contains("ld: 1 duplicate symbol for architecture arm64"))
        #expect(extracted.contains("clang: error: linker command failed"))
    }

    @Test
    func `Extracts undefined-symbol block with referenced-from objects`() {
        let raw = """
            SwiftCompile normal arm64 (in target 'App' from project 'App')
            Undefined symbols for architecture arm64:
              "_MissingSymbol", referenced from:
                  main.main() -> () in main.o
                  _foo in Helper.o
            ld: symbol(s) not found for architecture arm64
            clang: error: linker command failed with exit code 1 (use -v to see invocation)
            """

        let extracted = LinkerDiagnostics.extract(from: raw)

        #expect(extracted.contains("Undefined symbols for architecture arm64:"))
        #expect(extracted.contains("\"_MissingSymbol\", referenced from:"))
        #expect(extracted.contains("main.main() -> () in main.o"))
        #expect(extracted.contains("_foo in Helper.o"))
    }

    @Test
    func `Returns empty when no diagnostics present`() {
        let raw = """
            CompileSwift normal arm64
            ** BUILD SUCCEEDED **
            """

        #expect(LinkerDiagnostics.extract(from: raw).isEmpty)
    }

    @Test
    func `Separates non-adjacent diagnostic regions`() {
        let raw = """
            /App/File.swift:10:5: error: cannot find 'foo' in scope
                    foo()
                    ^~~
            some unrelated build progress line
            another unrelated line
            ld: framework not found SomeFramework
            clang: error: linker command failed with exit code 1
            """

        let extracted = LinkerDiagnostics.extract(from: raw)

        #expect(extracted.contains("cannot find 'foo' in scope"))
        #expect(extracted.contains("ld: framework not found SomeFramework"))
        // The unrelated middle lines must be dropped, replaced by an ellipsis separator.
        #expect(!extracted.contains("some unrelated build progress line"))
        #expect(extracted.contains("…"))
    }

    @Test
    func `Truncates when exceeding the line cap`() {
        var lines = ["duplicate symbol '_x' in:"]
        for index in 0..<50 { lines.append("    /path/to/object-\(index).o") }
        let raw = lines.joined(separator: "\n")

        let extracted = LinkerDiagnostics.extract(from: raw, maxLines: 10)

        #expect(extracted.contains("more diagnostic lines truncated"))
    }
}
