import Testing
@testable import XCMCPCore
import Foundation
import MCP

/// Regression coverage for `Swift.Error.asMCPError()`.
///
/// The MCP cancellation spec forbids sending any response (including an error)
/// for a cancelled request. The previous non-throwing `asMCPError()` quietly
/// converted `CancellationError` into `MCPError.internalError("CancellationError()")`,
/// which the SDK's request handler then sent on the wire. Claude Code treats
/// that protocol violation as fatal and tears down the stdio pipe — the
/// disconnect symptom in `0xp-xz6` / `ive-jzc`.
struct MCPErrorConvertibleTests {
    @Test
    func `asMCPError rethrows CancellationError`() {
        let error: any Swift.Error = CancellationError()
        #expect(throws: CancellationError.self) {
            _ = try error.asMCPError()
        }
    }

    @Test
    func `asMCPError returns existing MCPError unchanged`() throws {
        let original = MCPError.invalidParams("bad input")
        let converted = try original.asMCPError()
        if case .invalidParams(let message) = converted {
            #expect(message == "bad input")
        } else {
            Issue.record("expected invalidParams, got \(converted)")
        }
    }

    @Test
    func `asMCPError wraps arbitrary errors as internalError`() throws {
        struct Boom: Swift.Error, CustomStringConvertible {
            var description: String { "boom" }
        }
        let converted = try Boom().asMCPError()
        if case .internalError(let message?) = converted {
            #expect(message.contains("boom"))
        } else {
            Issue.record("expected internalError, got \(converted)")
        }
    }
}
