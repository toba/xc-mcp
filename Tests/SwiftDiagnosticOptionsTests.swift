import MCP
import Testing
import Foundation
@testable import XCMCPCore

/// Tests for the compiler-probe parameters `swift_package_build` and `swift_package_test` share.
struct SwiftDiagnosticOptionsTests {
    @Test
    func `a filter without a path is refused`() {
        let options = SwiftDiagnosticOptions(from: ["stderr_filter": .string("^BISECT")])

        #expect(throws: MCPError.self) { _ = try options.makeSink() }
    }

    @Test
    func `no diagnostic parameters produce no sink`() throws {
        let options = SwiftDiagnosticOptions(from: [:])

        #expect(options.swiftcFlags.isEmpty)
        #expect(try options.makeSink() == nil)
    }

    @Test
    func `compiler flags are read as an array of strings`() {
        let options = SwiftDiagnosticOptions(from: [
            "swiftc_flags": .array([.string("-Xllvm"), .string("-inline-threshold=0")])
        ])

        #expect(options.swiftcFlags == ["-Xllvm", "-inline-threshold=0"])
    }

    @Test
    func `a non-string entry in the flag array is dropped`() {
        let options = SwiftDiagnosticOptions(from: [
            "swiftc_flags": .array([.string("-Xllvm"), .int(7)])
        ])

        #expect(options.swiftcFlags == ["-Xllvm"])
    }
}
