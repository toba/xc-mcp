import Testing
import Foundation
@testable import XCMCPCore

struct MachOInspectorTests {
    // MARK: - size -m

    @Test func `parses segments and excludes __PAGEZERO`() {
        let output = """
        Segment __PAGEZERO: 4294967296
        Segment __TEXT: 16384
        \tSection __text: 7264
        \tSection __stubs: 348
        \ttotal 8618
        Segment __DATA_CONST: 16384
        Segment __LINKEDIT: 32768
        total 4294983680
        """
        let segments = MachOInspector.parseSegments(output)
        #expect(segments == [
            .init(name: "__TEXT", size: 16384),
            .init(name: "__DATA_CONST", size: 16384),
            .init(name: "__LINKEDIT", size: 32768),
        ])
    }

    @Test func `returns no segments for empty output`() {
        #expect(MachOInspector.parseSegments("").isEmpty)
    }

    // MARK: - otool -L

    @Test func `parses linked libraries and strips compatibility suffix`() {
        let output = """
        /var/tmp/b:
        \t@rpath/Ulysses.framework/Versions/A/Ulysses (compatibility version 1.0.0, current version 1.0.0)
        \t@rpath/ThesisApp (debug).debug.dylib (compatibility version 0.0.0, current version 0.0.0)
        \t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
        """
        let libs = MachOInspector.parseLinkedLibraries(output)
        #expect(libs.map(\.path) == [
            "@rpath/Ulysses.framework/Versions/A/Ulysses",
            "@rpath/ThesisApp (debug).debug.dylib",
            "/usr/lib/libSystem.B.dylib",
        ])
    }

    @Test func `classifies relative vs absolute deps`() {
        let libs = MachOInspector.parseLinkedLibraries("""
        /var/tmp/b:
        \t@rpath/Foo.framework/Foo (compatibility version 1.0.0, current version 1.0.0)
        \t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)
        """)
        #expect(libs.filter(\.isRelative).map(\.path) == ["@rpath/Foo.framework/Foo"])
    }

    // MARK: - otool -l (LC_RPATH)

    @Test func `parses LC_RPATH entries and strips offset suffix`() {
        let output = """
        Load command 20
                  cmd LC_RPATH
              cmdsize 32
                 path @executable_path (offset 12)
        Load command 21
                  cmd LC_RPATH
              cmdsize 136
                 path /Users/x/DerivedData/App/Build/Products/Debug/PackageFrameworks (offset 12)
        Load command 22
                  cmd LC_RPATH
              cmdsize 48
                 path @executable_path/../Frameworks (offset 12)
        Load command 23
                  cmd LC_CODE_SIGNATURE
              cmdsize 16
        """
        #expect(MachOInspector.parseRpaths(output) == [
            "@executable_path",
            "/Users/x/DerivedData/App/Build/Products/Debug/PackageFrameworks",
            "@executable_path/../Frameworks",
        ])
    }

    @Test func `does not treat a path in a non-rpath command as an rpath`() {
        // A `path` field only counts when it immediately follows `cmd LC_RPATH`.
        let output = """
                  cmd LC_LOAD_DYLIB
              cmdsize 56
                 path @rpath/Other.dylib (offset 24)
        """
        #expect(MachOInspector.parseRpaths(output).isEmpty)
    }

    // MARK: - nm

    @Test func `counts relinkable library class markers`() {
        let output = """
        0000000100000000 S _relinkableLibraryClasses
        0000000100000010 S _relinkableLibraryClasses
        0000000100000020 T _main
        """
        #expect(MachOInspector.countRelinkableClasses(output) == 2)
        #expect(MachOInspector.countRelinkableClasses("0000 T _main") == 0)
    }

    // MARK: - lipo

    @Test func `parses architectures`() {
        #expect(MachOInspector.parseArchitectures("x86_64 arm64\n") == ["x86_64", "arm64"])
        #expect(MachOInspector.parseArchitectures("arm64") == ["arm64"])
    }

    // MARK: - dyld resolution

    @Test func `resolves @rpath dep via @executable_path rpath inside the bundle`() {
        // @rpath/App.debug.dylib with rpath @executable_path resolves to Contents/MacOS/App.debug.dylib.
        let app = "/App.app"
        let exeDir = "/App.app/Contents/MacOS"
        let embedded = "/App.app/Contents/MacOS/App.debug.dylib"
        let resolved = MachOInspector.resolvesInsideBundle(
            dep: .init(path: "@rpath/App.debug.dylib"),
            rpaths: ["@executable_path", "@executable_path/../Frameworks"],
            appPath: app,
            executableDir: exeDir,
            fileExists: { $0 == embedded },
        )
        #expect(resolved)
    }

    @Test func `resolves @rpath framework via ..-Frameworks rpath`() {
        let resolved = MachOInspector.resolvesInsideBundle(
            dep: .init(path: "@rpath/Ulysses.framework/Versions/A/Ulysses"),
            rpaths: ["@executable_path/../Frameworks"],
            appPath: "/App.app",
            executableDir: "/App.app/Contents/MacOS",
            fileExists: { $0 == "/App.app/Contents/Frameworks/Ulysses.framework/Versions/A/Ulysses" },
        )
        #expect(resolved)
    }

    @Test func `flags dep that only resolves via an absolute dev-time rpath outside the bundle`() {
        // The package framework exists only under an absolute DerivedData PackageFrameworks path —
        // outside the bundle — so it is NOT self-contained.
        let outside = "/Users/x/DerivedData/App/Build/Products/Debug/PackageFrameworks/Pkg.framework/Pkg"
        let resolved = MachOInspector.resolvesInsideBundle(
            dep: .init(path: "@rpath/Pkg.framework/Pkg"),
            rpaths: [
                "@executable_path/../Frameworks",
                "/Users/x/DerivedData/App/Build/Products/Debug/PackageFrameworks",
            ],
            appPath: "/App.app",
            executableDir: "/App.app/Contents/MacOS",
            fileExists: { $0 == outside },
        )
        #expect(!resolved)
    }

    @Test func `absolute system deps never resolve inside the bundle`() {
        let resolved = MachOInspector.resolvesInsideBundle(
            dep: .init(path: "/usr/lib/libSystem.B.dylib"),
            rpaths: ["@executable_path"],
            appPath: "/App.app",
            executableDir: "/App.app/Contents/MacOS",
            fileExists: { _ in true },
        )
        #expect(!resolved)
    }
}
