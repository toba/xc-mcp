import XCMCPCore
import Foundation
import Subprocess

/// The signed product types the `notarize` verify action checks
enum SignedProductKind: Sendable, Equatable {
    case app
    case pkg
    case dmg

    /// Reads the kind from the path extension, or `nil` for an unsupported product.
    init?(path: String) {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
            case "app": self = .app
            case "pkg": self = .pkg
            case "dmg": self = .dmg
            default: return nil
        }
    }

    /// The signature, stapled-ticket and Gatekeeper checks for the product at `path`, in run order
    ///
    /// A flat installer package carries an installer signature that `codesign` cannot read, so a
    /// `.pkg` checks its signature with `pkgutil` instead.
    func checks(path: String) -> [VerificationCheck] {
        let signature =
            switch self {
                case .pkg:
                    VerificationCheck(
                        role: .signature, executable: "pkgutil",
                        arguments: ["--check-signature", path],
                    )
                case .app, .dmg:
                    VerificationCheck(
                        role: .signature, executable: "codesign",
                        arguments: ["--verify", "--deep", "--strict", "--verbose=2", path],
                    )
            }
        let assessment: [String] =
            switch self {
                case .app: ["--type", "exec"]
                case .pkg: ["--type", "install"]
                case .dmg: ["--type", "open", "--context", "context:primary-signature"]
            }
        return [
            signature,
            VerificationCheck(
                role: .stapledTicket, executable: "xcrun",
                arguments: ["stapler", "validate", path],
            ),
            VerificationCheck(
                role: .gatekeeper, executable: "spctl",
                arguments: ["--assess", "-vvv"] + assessment + [path],
            ),
        ]
    }
}

/// One command the verify action runs, and the label the report gives it
struct VerificationCheck: Sendable, Equatable {
    enum Role: Sendable, Equatable { case signature, stapledTicket, gatekeeper }

    let role: Role
    let executable: String
    let arguments: [String]

    var name: String {
        switch role {
            case .signature: "Signature"
            case .stapledTicket: "Stapled ticket"
            case .gatekeeper: "Gatekeeper"
        }
    }

    /// The command line without the product path, for the report heading.
    var commandLine: String { ([executable] + arguments.dropLast()).joined(separator: " ") }

    /// Runs the check and turns a timeout or a launch failure into a failed result.
    func run() async throws -> VerificationOutcome {
        let result: ProcessResult

        do {
            result = try await ProcessResult.runSubprocess(
                .name(executable), arguments: Arguments(arguments), timeout: .seconds(180),
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result = ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }
        return .init(check: self, result: result)
    }
}

/// A check paired with the process result it produced
struct VerificationOutcome: Sendable {
    let check: VerificationCheck
    let result: ProcessResult

    var passed: Bool { result.succeeded }
}

/// The text the verify action returns for a set of check outcomes
///
/// A nonzero exit is a failed check, not a tool error, so the report always renders. When the
/// signature holds but Gatekeeper rejects the product, the report says the likely cause: a
/// Developer ID product that is not notarized.
struct VerificationReport: Sendable {
    let path: String
    let outcomes: [VerificationOutcome]

    var passed: Bool { outcomes.allSatisfy(\.passed) }

    private func outcome(_ role: VerificationCheck.Role) -> VerificationOutcome? {
        outcomes.first { $0.check.role == role }
    }

    /// The value of the `source=` line that `spctl` prints, such as `Notarized Developer ID`.
    var gatekeeperSource: String? {
        outcome(.gatekeeper)?.result.output
            .split(separator: "\n")
            .first { $0.hasPrefix("source=") }
            .map { String($0.dropFirst("source=".count)) }
    }

    var text: String {
        let failures = outcomes.count { !$0.passed }
        var lines = [
            passed
                ? "Verification of \(path): PASS (\(outcomes.count) checks passed)"
                : "Verification of \(path): FAIL (\(failures) of \(outcomes.count) checks failed)"
        ]

        if let gatekeeperSource { lines.append("Gatekeeper source: \(gatekeeperSource)") }

        for outcome in outcomes {
            lines.append("")
            lines.append(
                "[\(outcome.passed ? "PASS" : "FAIL")] \(outcome.check.name) (\(outcome.check.commandLine))",
            )
            let output = outcome.result.output.trimmingCharacters(in: .whitespacesAndNewlines)

            if !output.isEmpty {
                lines += output.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "  \($0)" }
            }
        }

        if outcome(.signature)?.passed == true, outcome(.gatekeeper)?.passed == false {
            lines.append("")
            lines.append(
                "The signature is valid, but Gatekeeper rejects the product. A Developer ID product that is not notarized fails this way. Run the 'submit' action, then 'staple', then verify again.",
            )
        }

        return lines.joined(separator: "\n")
    }
}
