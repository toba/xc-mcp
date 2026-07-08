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
        #expect(
            segments == [
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
        #expect(
            libs.map(
                \.path) == [
                    "@rpath/Ulysses.framework/Versions/A/Ulysses",
                    "@rpath/ThesisApp (debug).debug.dylib",
                    "/usr/lib/libSystem.B.dylib",
                ])
    }

    @Test func `classifies relative vs absolute deps`() {
        let libs = MachOInspector.parseLinkedLibraries(
            """
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
        #expect(
            MachOInspector.parseRpaths(
                output) == [
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
        // @rpath/App.debug.dylib with rpath @executable_path resolves to
        // Contents/MacOS/App.debug.dylib.
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
            fileExists: {
                $0 == "/App.app/Contents/Frameworks/Ulysses.framework/Versions/A/Ulysses"
            },
        )
        #expect(resolved)
    }

    @Test func `flags dep that only resolves via an absolute dev-time rpath outside the bundle`() {
        // The package framework exists only under an absolute DerivedData PackageFrameworks path —
        // outside the bundle — so it is NOT self-contained.
        let outside =
            "/Users/x/DerivedData/App/Build/Products/Debug/PackageFrameworks/Pkg.framework/Pkg"
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

    @Test func `resolves a framework @loader_path dep against its own directory`() {
        // A framework linking @loader_path/Helper.dylib resolves next to the framework binary.
        let resolved = MachOInspector.resolves(
            dep: .init(path: "@loader_path/Helper.dylib"),
            rpaths: [],
            loaderDir: "/App.app/Contents/Frameworks/Foo.framework/Versions/A",
            executableDir: "/App.app/Contents/MacOS",
            appPath: "/App.app",
            fileExists: {
                $0 == "/App.app/Contents/Frameworks/Foo.framework/Versions/A/Helper.dylib"
            },
        )
        #expect(resolved)
    }

    // MARK: - full closure

    @Test func `closure is self-contained when every image dep resolves inside the bundle`() {
        // Main exe links @rpath/Foo.framework/Foo (embedded); Foo links @rpath/Bar.framework/Bar
        // (also embedded). Both resolve via the executable's @executable_path/../Frameworks rpath.
        let app = "/App.app"
        let frameworks = "/App.app/Contents/Frameworks"
        let onDisk: Set<String> = [
            "\(frameworks)/Foo.framework/Foo",
            "\(frameworks)/Bar.framework/Bar",
        ]
        let images = [
            MachOInspector.MachOImage(
                name: "App (main executable)",
                loaderDir: "\(app)/Contents/MacOS",
                rpaths: ["@executable_path/../Frameworks"],
                relativeDeps: [.init(path: "@rpath/Foo.framework/Foo")],
            ),
            MachOInspector.MachOImage(
                name: "Foo.framework",
                loaderDir: "\(frameworks)/Foo.framework",
                rpaths: [],
                relativeDeps: [.init(path: "@rpath/Bar.framework/Bar")],
            ),
        ]
        let missing = MachOInspector.unresolvedClosure(
            images: images,
            executableDir: "\(app)/Contents/MacOS",
            executableRpaths: ["@executable_path/../Frameworks"],
            appPath: app,
            fileExists: { onDisk.contains($0) },
        )
        #expect(missing.isEmpty)
    }

    @Test func `closure flags a transitive framework dep the app binary alone would miss`() {
        // The app binary is fully self-contained, but an embedded framework (EPUB) links a
        // package-product framework (ZIPFoundation) that is NOT embedded — the false-positive case.
        let app = "/App.app"
        let frameworks = "/App.app/Contents/Frameworks"
        let onDisk: Set<String> = [
            "\(frameworks)/EPUB.framework/EPUB"
            // ZIPFoundation is deliberately absent.
        ]
        let images = [
            MachOInspector.MachOImage(
                name: "App (main executable)",
                loaderDir: "\(app)/Contents/MacOS",
                rpaths: ["@executable_path/../Frameworks"],
                relativeDeps: [.init(path: "@rpath/EPUB.framework/EPUB")],
            ),
            MachOInspector.MachOImage(
                name: "EPUB.framework",
                loaderDir: "\(frameworks)/EPUB.framework",
                rpaths: [],
                relativeDeps: [.init(path: "@rpath/ZIPFoundation.framework/ZIPFoundation")],
            ),
        ]
        let missing = MachOInspector.unresolvedClosure(
            images: images,
            executableDir: "\(app)/Contents/MacOS",
            executableRpaths: ["@executable_path/../Frameworks"],
            appPath: app,
            fileExists: { onDisk.contains($0) },
        )
        #expect(missing.map(\.dep) == ["@rpath/ZIPFoundation.framework/ZIPFoundation"])
        #expect(missing.first?.referencedBy == ["EPUB.framework"])
    }

    @Test func `closure attributes one missing dep to every image that references it`() {
        let app = "/App.app"
        let images = [
            MachOInspector.MachOImage(
                name: "B.framework",
                loaderDir: "\(app)/Contents/Frameworks/B.framework",
                rpaths: [],
                relativeDeps: [.init(path: "@rpath/Missing.framework/Missing")],
            ),
            MachOInspector.MachOImage(
                name: "A.framework",
                loaderDir: "\(app)/Contents/Frameworks/A.framework",
                rpaths: [],
                relativeDeps: [.init(path: "@rpath/Missing.framework/Missing")],
            ),
        ]
        let missing = MachOInspector.unresolvedClosure(
            images: images,
            executableDir: "\(app)/Contents/MacOS",
            executableRpaths: ["@executable_path/../Frameworks"],
            appPath: app,
            fileExists: { _ in false },
        )
        #expect(missing.count == 1)
        // referencedBy is sorted for stable output regardless of image order.
        #expect(missing.first?.referencedBy == ["A.framework", "B.framework"])
    }

    // MARK: - OS-provided runtime

    @Test func `classifies @rpath libswift dylibs as OS-provided runtime`() {
        #expect(MachOInspector.isOSProvidedRuntime("@rpath/libswiftCore.dylib"))
        #expect(MachOInspector.isOSProvidedRuntime("@rpath/libswiftFoundation.dylib"))
        #expect(MachOInspector.isOSProvidedRuntime("@rpath/libswiftObjectiveC.dylib"))
    }

    @Test func `does not classify embedded frameworks or absolute libs as OS-provided runtime`() {
        // A real embedding gap (package-product framework) must stay in the "missing" bucket.
        #expect(!MachOInspector.isOSProvidedRuntime("@rpath/ZIPFoundation.framework/ZIPFoundation"))
        // An absolute Swift runtime path is not @rpath-linked, so it never counts as unresolved.
        #expect(!MachOInspector.isOSProvidedRuntime("/usr/lib/swift/libswiftCore.dylib"))
        // A non-Swift @rpath dylib is a genuine dependency, not the OS runtime.
        #expect(!MachOInspector.isOSProvidedRuntime("@rpath/libMyHelper.dylib"))
    }
}
