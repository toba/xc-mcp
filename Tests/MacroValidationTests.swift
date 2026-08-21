import Testing
import Foundation
@testable import XCMCPCore

struct MacroValidationTests {
    @Test func `passes the flag by default`() {
        #expect(MacroValidation.args(environment: [:]) == ["-skipMacroValidation"])
    }

    @Test func `omits the flag when the caller already passed it`() {
        let args = MacroValidation.args(
            additionalArguments: ["-skipMacroValidation"], environment: [:],
        )
        #expect(args.isEmpty)
    }

    @Test func `omits the flag when the environment requires approval`() {
        let args = MacroValidation.args(
            environment: ["XC_MCP_REQUIRE_MACRO_APPROVAL": "1"],
        )
        #expect(args.isEmpty)
    }

    @Test func `treats 0 and false as not requiring approval`() {
        #expect(
            MacroValidation.args(environment: ["XC_MCP_REQUIRE_MACRO_APPROVAL": "0"])
                == ["-skipMacroValidation"],
        )
        #expect(
            MacroValidation.args(environment: ["XC_MCP_REQUIRE_MACRO_APPROVAL": "false"])
                == ["-skipMacroValidation"],
        )
    }
}

struct MacroApprovalAdviceTests {
    private static let failure = """
        error: Macro "TobaDependencyMacros" from package "toba-dependency" was changed since a \
        previous approval and must be enabled before it can be used
        """

    @Test func `detects the approval failure`() {
        #expect(MacroApprovalAdvice.isMacroApprovalFailure(Self.failure))
    }

    @Test func `ignores unrelated build output`() {
        #expect(!MacroApprovalAdvice.isMacroApprovalFailure("error: cannot find 'Foo' in scope"))
        #expect(MacroApprovalAdvice.advice(for: "** BUILD SUCCEEDED **") == nil)
    }

    @Test func `advice names the flag`() {
        let advice = MacroApprovalAdvice.advice(for: Self.failure)
        #expect(advice?.contains("-skipMacroValidation") == true)
    }

    /// Xcode uses the same wording for a package plugin, which needs a different flag. The word
    /// `macro` appearing on some other line of a long log must not draw macro advice.
    @Test func `ignores a plugin approval failure in a log that mentions a macro`() {
        let log = """
            warning: macro expansion produced no declarations
            Compiling AppFeature
            error: Plugin "SwiftLintPlugin" from package "swiftlint" must be enabled before it can \
            be used
            """
        #expect(!MacroApprovalAdvice.isMacroApprovalFailure(log))
        #expect(MacroApprovalAdvice.advice(for: log) == nil)
    }

    @Test func `detects the approval failure inside a long log`() {
        let log = """
            Compiling AppFeature
            error: Macro "AppMacros" from package "app-macros" must be enabled before it can be used
            ** BUILD FAILED **
            """
        #expect(MacroApprovalAdvice.isMacroApprovalFailure(log))
    }
}
