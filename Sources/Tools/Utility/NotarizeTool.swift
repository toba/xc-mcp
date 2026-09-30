import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Manages macOS app notarization using `notarytool` and `stapler`.
///
/// Wraps `xcrun notarytool` and `xcrun stapler` for submitting apps to Apple's notarization
/// service, checking submission status, retrieving logs, and stapling tickets to binaries. The
/// `verify` action confirms the result with `codesign`, `stapler validate` and `spctl`.
///
/// ## Example
///
/// ```
/// notarize(action: "submit", path: "/path/to/app.dmg", keychain_profile: "AC_PASSWORD")
/// notarize(action: "status", submission_id: "abc-123", keychain_profile: "AC_PASSWORD")
/// notarize(action: "staple", path: "/path/to/app.dmg")
/// notarize(action: "verify", path: "/path/to/App.app")
/// ```
public struct NotarizeTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "notarize",
            description:
                "Manage macOS app notarization. Submit apps/dmgs/pkgs to Apple for notarization, check submission status, retrieve notarization logs, staple tickets, and verify that Gatekeeper accepts the signed and stapled product. Submit, status, log, and history require a keychain profile configured via 'xcrun notarytool store-credentials'.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("submit"),
                            .string("status"),
                            .string("log"),
                            .string("staple"),
                            .string("history"),
                            .string("verify"),
                        ]),
                        "description": .string(
                            "Action: 'submit' sends for notarization, 'status' checks a submission, 'log' retrieves rejection details, 'staple' attaches ticket to binary, 'history' lists recent submissions, 'verify' checks the signature, the stapled ticket, and Gatekeeper acceptance.",
                        ),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the app, dmg, or pkg file. Required for submit, staple, and verify.",
                        ),
                    ]),
                    "keychain_profile": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Keychain profile name for authentication (created via 'xcrun notarytool store-credentials'). Required for submit, status, log, and history.",
                        ),
                    ]),
                    "submission_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Submission ID to query. Required for status and log actions.",
                        ),
                    ]),
                    "wait": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Wait for notarization to complete (submit only). Default: true.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Timeout in minutes for submit --wait. Default: 30."),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let action = try arguments.getRequiredString("action")

        switch action {
            case "submit": return try await submit(arguments: arguments)
            case "status": return try await status(arguments: arguments)
            case "log": return try await log(arguments: arguments)
            case "staple": return try await staple(arguments: arguments)
            case "history": return try await history(arguments: arguments)
            case "verify": return try await verify(arguments: arguments)
            default:
                throw MCPError.invalidParams(
                    "Unknown action '\(action)'. Use submit, status, log, staple, history, or verify.",
                )
        }
    }

    private func submit(arguments: [String: Value]) async throws -> CallTool.Result {
        let path = try arguments.getRequiredString("path")
        let profile = try arguments.getRequiredString("keychain_profile")
        let wait = arguments.getBool("wait", default: true)
        let timeoutMinutes = arguments.getInt("timeout") ?? 30

        var args = ["notarytool", "submit", path, "--keychain-profile", profile]
        if wait { args.append("--wait") }

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(args),
            timeout: .seconds(timeoutMinutes * 60 + 30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "notarytool submit failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result.text(result.stdout)
    }

    private func status(arguments: [String: Value]) async throws -> CallTool.Result {
        let submissionID = try arguments.getRequiredString("submission_id")
        let profile = try arguments.getRequiredString("keychain_profile")

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments([
                "notarytool", "info", submissionID, "--keychain-profile", profile,
            ]),
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "notarytool info failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result.text(result.stdout)
    }

    private func log(arguments: [String: Value]) async throws -> CallTool.Result {
        let submissionID = try arguments.getRequiredString("submission_id")
        let profile = try arguments.getRequiredString("keychain_profile")

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["notarytool", "log", submissionID, "--keychain-profile", profile]
            ),
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "notarytool log failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result.text(result.stdout)
    }

    private func staple(arguments: [String: Value]) async throws -> CallTool.Result {
        let path = try arguments.getRequiredString("path")

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["stapler", "staple", path]),
            timeout: .seconds(60),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "stapler failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result.text(result.stdout)
    }

    private func history(arguments: [String: Value]) async throws -> CallTool.Result {
        let profile = try arguments.getRequiredString("keychain_profile")

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["notarytool", "history", "--keychain-profile", profile]),
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "notarytool history failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        return CallTool.Result.text(result.stdout)
    }

    /// Runs the signature, stapled-ticket and Gatekeeper checks and reports each one
    ///
    /// The checks run at once, and every check runs when another one fails. A rejected product
    /// returns a report, not a tool error.
    private func verify(arguments: [String: Value]) async throws -> CallTool.Result {
        let path = try arguments.getRequiredString("path")

        guard FileManager.default.fileExists(atPath: path) else {
            throw MCPError.invalidParams("Path does not exist: \(path)")
        }
        guard let kind = SignedProductKind(path: path) else {
            throw MCPError.invalidParams(
                "verify supports .app, .pkg, and .dmg products, got: \(path)",
            )
        }

        let checks = kind.checks(path: path)
        let outcomes = try await withThrowingTaskGroup(
            of: (Int, VerificationOutcome).self,
        ) { group in
            for (index, check) in checks.enumerated() {
                group.addTask(name: "notarize verify \(check.name)") {
                    try await (index, check.run())
                }
            }
            var ordered = [VerificationOutcome?](repeating: nil, count: checks.count)
            for try await (index, outcome) in group { ordered[index] = outcome }
            return ordered.compactMap(\.self)
        }

        return CallTool.Result.text(VerificationReport(path: path, outcomes: outcomes).text)
    }
}
