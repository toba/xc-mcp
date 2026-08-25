import Testing
@testable import XCMCPCore

struct VisibleModuleListTests {
    /// The shape `swift-symbolgraph-extract` writes when it cannot load a module.
    private func failureOutput(_ names: [String]) -> String {
        """
        Couldn't load module 'OrderedCollections' in the current SDK and search paths.
        Current visible modules:
        \(names.joined(separator: "\n"))
        """
    }

    // MARK: - Parsing

    @Test
    func `Parse reads the names under the visible modules line`() {
        let names = VisibleModuleList.parse(failureOutput(["AppKit", "Combine", "SwiftUI"]))
        #expect(names == ["AppKit", "Combine", "SwiftUI"])
    }

    @Test
    func `Parse returns nothing when the marker is absent`() {
        #expect(VisibleModuleList.parse("error: no such file or directory").isEmpty)
    }

    @Test
    func `Parse skips blank lines`() {
        let output = """
            Current visible modules:
            AppKit

            Combine
            """
        #expect(VisibleModuleList.parse(output) == ["AppKit", "Combine"])
    }

    // MARK: - Ranking

    @Test
    func `Closest caps the result at ten names`() {
        let names = (1...40).map { "Module\($0)" }
        let closest = VisibleModuleList.closest(to: "OrderedCollections", in: failureOutput(names))
        #expect(closest.count == 10)
    }

    @Test
    func `Closest puts a containing name first`() {
        let output = failureOutput(["Accelerate", "AppKit", "CollectionsX", "SwiftUI"])
        let closest = VisibleModuleList.closest(to: "Collections", in: output)
        #expect(closest.first == "CollectionsX")
    }

    @Test
    func `Closest prefers the nearer spelling`() {
        let output = failureOutput(["ARKit", "Swift", "SwiftUIX"])
        let closest = VisibleModuleList.closest(to: "SwiftUI", in: output)
        #expect(closest.first == "SwiftUIX")
        #expect(closest[1] == "Swift")
    }

    @Test
    func `Closest drops the underscored clang submodules`() {
        let output = failureOutput(["_Builtin_stdarg", "_xlocale_wctype_h", "Combine"])
        #expect(VisibleModuleList.closest(to: "OrderedCollections", in: output) == ["Combine"])
    }

    @Test
    func `Closest keeps underscored names when the request is underscored`() {
        let output = failureOutput(["_Builtin_stdarg", "Combine"])
        let closest = VisibleModuleList.closest(to: "_Builtin_float", in: output)
        #expect(closest.contains("_Builtin_stdarg"))
    }

    @Test
    func `Closest is case insensitive`() {
        let output = failureOutput(["Accelerate", "combinex", "SwiftUI"])
        #expect(VisibleModuleList.closest(to: "Combine", in: output).first == "combinex")
    }

    @Test
    func `Closest returns nothing when the marker is absent`() {
        #expect(VisibleModuleList.closest(to: "SwiftUI", in: "linker command failed").isEmpty)
    }
}
