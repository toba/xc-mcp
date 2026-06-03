import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Exports a built `.xcarchive` into a distributable `.pkg` / `.ipa` (and optionally uploads it
/// to App Store Connect) via `xcodebuild -exportArchive`.
///
/// Companion to ``ArchiveTool``: the archive tool produces an `.xcarchive` bundle on disk and
/// stops there. Without this tool the agentic loop has to bounce to Xcode Organizer or
/// Transporter to actually ship the build. With it, archive → export → upload is one chain of
/// tool calls.
///
/// Notes on `-exportArchive` quirks:
///
/// - The build system rejects the deprecated pre-Xcode-16 method names (`app-store`, `ad-hoc`,
///   `development`). This tool accepts only the current spellings and surfaces the typo back to
///   the caller before invoking xcodebuild.
/// - `-allowProvisioningUpdates` is always passed. Without it the build system won't regenerate
///   missing distribution profiles, which is what trips up most "works in Xcode UI, fails from
///   the CLI" reports.
/// - The synthesized `ExportOptions.plist` is written next to the export output so the caller
///   can inspect what was actually sent to xcodebuild.
public struct ExportArchiveTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner

    /// Xcode 16+ distribution methods accepted by `-exportArchive`.
    private static let validMethods: Set<String> = [
        "app-store-connect",
        "release-testing",
        "debugging",
        "enterprise",
        "developer-id",
        "mac-application",
    ]

    private static let deprecatedMethodMap: [String: String] = [
        "app-store": "app-store-connect",
        "ad-hoc": "release-testing",
        "development": "debugging",
    ]

    public init(xcodebuildRunner: XcodebuildRunner = XcodebuildRunner()) {
        self.xcodebuildRunner = xcodebuildRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "export_archive",
            description:
                "Export a built .xcarchive into a distributable .pkg/.ipa via "
                + "`xcodebuild -exportArchive`, or upload it directly to App Store Connect. "
                + "Synthesizes ExportOptions.plist from the supplied parameters and passes "
                + "-allowProvisioningUpdates so missing distribution profiles get regenerated "
                + "automatically. Companion to the `archive` tool — closes the archive → export "
                + "→ upload loop without bouncing to Xcode Organizer or Transporter.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "archive_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to an existing .xcarchive bundle (produced by the `archive` "
                            + "tool or Xcode). Required.",
                        ),
                    ]),
                    "export_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory where the exported .pkg/.ipa and the synthesized "
                            + "ExportOptions.plist are written. Created if it doesn't exist. "
                            + "Required.",
                        ),
                    ]),
                    "method": .object([
                        "type": .string("string"),
                        "enum": .array(Self.validMethods.sorted().map { .string($0) }),
                        "description": .string(
                            "Distribution method. Xcode 16+ spellings only — "
                            + "`app-store-connect`, `release-testing`, `debugging`, `enterprise`, "
                            + "`developer-id`, `mac-application`. The deprecated pre-16 names "
                            + "(`app-store`, `ad-hoc`, `development`) are rejected with a hint.",
                        ),
                    ]),
                    "team_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Apple Developer team ID (`teamID` in ExportOptions.plist). "
                            + "Defaults to the project's DEVELOPMENT_TEAM if omitted.",
                        ),
                    ]),
                    "signing_style": .object([
                        "type": .string("string"),
                        "enum": .array([.string("automatic"), .string("manual")]),
                        "description": .string(
                            "`automatic` (default) lets Xcode pick/generate profiles. "
                            + "`manual` requires `provisioning_profiles` to map each bundle ID "
                            + "to a profile name.",
                        ),
                    ]),
                    "provisioning_profiles": .object([
                        "type": .string("object"),
                        "additionalProperties": .object(["type": .string("string")]),
                        "description": .string(
                            "Map of bundle identifier → provisioning profile name (or UUID). "
                            + "Only used when `signing_style` is `manual`.",
                        ),
                    ]),
                    "destination": .object([
                        "type": .string("string"),
                        "enum": .array([.string("export"), .string("upload")]),
                        "description": .string(
                            "`export` (default) writes artifacts to `export_path`. `upload` "
                            + "delivers the build straight to App Store Connect — requires the "
                            + "`api_key_*` parameters.",
                        ),
                    ]),
                    "api_key_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "App Store Connect API key ID. Required when `destination=upload`.",
                        ),
                    ]),
                    "api_key_issuer_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "App Store Connect API key issuer ID. Required when "
                            + "`destination=upload`.",
                        ),
                    ]),
                    "api_key_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .p8 API key file. Required when `destination=upload`.",
                        ),
                    ]),
                    "timeout": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Maximum time in seconds for the export step. Defaults to 600.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("archive_path"),
                    .string("export_path"),
                    .string("method"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let archivePath = try arguments.getRequiredString("archive_path")
        let exportPath = try arguments.getRequiredString("export_path")
        let methodRaw = try arguments.getRequiredString("method")
        let teamID = arguments.getString("team_id")
        let signingStyle = arguments.getString("signing_style") ?? "automatic"
        let destination = arguments.getString("destination") ?? "export"
        let timeout = arguments.getInt("timeout").map { TimeInterval($0) } ?? 600

        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw MCPError.invalidParams(
                "archive_path does not exist: \(archivePath)",
            )
        }

        let method = try validateMethod(methodRaw)

        guard signingStyle == "automatic" || signingStyle == "manual" else {
            throw MCPError.invalidParams(
                "signing_style must be 'automatic' or 'manual' (got '\(signingStyle)')",
            )
        }

        let provisioningProfiles = arguments.getStringDictionary("provisioning_profiles")
        if signingStyle == "manual", provisioningProfiles.isEmpty {
            throw MCPError.invalidParams(
                "signing_style=manual requires provisioning_profiles "
                + "(map of bundle ID → profile name)",
            )
        }

        guard destination == "export" || destination == "upload" else {
            throw MCPError.invalidParams(
                "destination must be 'export' or 'upload' (got '\(destination)')",
            )
        }

        let apiKeyID = arguments.getString("api_key_id")
        let apiKeyIssuerID = arguments.getString("api_key_issuer_id")
        let apiKeyPath = arguments.getString("api_key_path")
        if destination == "upload" {
            guard apiKeyID != nil, apiKeyIssuerID != nil, apiKeyPath != nil else {
                throw MCPError.invalidParams(
                    "destination=upload requires api_key_id, api_key_issuer_id, and api_key_path",
                )
            }
        }

        try FileManager.default.createDirectory(
            atPath: exportPath, withIntermediateDirectories: true,
        )

        let plistPath = (exportPath as NSString).appendingPathComponent("ExportOptions.plist")
        try writeExportOptionsPlist(
            to: plistPath,
            method: method,
            destination: destination,
            teamID: teamID,
            signingStyle: signingStyle,
            provisioningProfiles: provisioningProfiles,
        )

        var args: [String] = [
            "-exportArchive",
            "-archivePath", archivePath,
            "-exportPath", exportPath,
            "-exportOptionsPlist", plistPath,
            "-allowProvisioningUpdates",
        ]

        if destination == "upload",
           let apiKeyID, let apiKeyIssuerID, let apiKeyPath {
            args += [
                "-authenticationKeyID", apiKeyID,
                "-authenticationKeyIssuerID", apiKeyIssuerID,
                "-authenticationKeyPath", apiKeyPath,
            ]
        }

        do {
            let result = try await xcodebuildRunner.run(
                arguments: args,
                timeout: timeout,
                onProgress: nil,
            )

            guard result.exitCode == 0 else {
                throw MCPError.internalError(
                    "xcodebuild -exportArchive failed (exit \(result.exitCode)):\n\(result.output)",
                )
            }

            let exported = exportedArtifacts(in: exportPath)
            let submissionID = extractSubmissionID(from: result.output)

            var text: String
            if destination == "upload" {
                text = "Upload to App Store Connect succeeded."
                if let submissionID { text += " Submission ID: \(submissionID)." }
                text += "\nExportOptions.plist: \(plistPath)"
            } else {
                text = "Export succeeded."
                if exported.isEmpty {
                    text += " (No .pkg/.ipa found in \(exportPath) — check the build log.)"
                } else {
                    text += "\nArtifacts:\n" + exported.map { "  - \($0)" }.joined(separator: "\n")
                }
                text += "\nExportOptions.plist: \(plistPath)"
            }

            return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw try error.asMCPError()
        }
    }

    private func validateMethod(_ method: String) throws -> String {
        if Self.validMethods.contains(method) { return method }
        if let modern = Self.deprecatedMethodMap[method] {
            throw MCPError.invalidParams(
                "method '\(method)' is the pre-Xcode-16 spelling and is no longer accepted by "
                + "`xcodebuild -exportArchive`. Use '\(modern)' instead.",
            )
        }
        let valid = Self.validMethods.sorted().joined(separator: ", ")
        throw MCPError.invalidParams(
            "method '\(method)' is not a valid distribution method. Expected one of: \(valid).",
        )
    }

    private func writeExportOptionsPlist(
        to path: String,
        method: String,
        destination: String,
        teamID: String?,
        signingStyle: String,
        provisioningProfiles: [String: String],
    ) throws {
        var plist: [String: Any] = [
            "method": method,
            "destination": destination,
            "signingStyle": signingStyle,
        ]
        if let teamID { plist["teamID"] = teamID }
        if !provisioningProfiles.isEmpty {
            plist["provisioningProfiles"] = provisioningProfiles
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0,
        )
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func exportedArtifacts(in directory: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return entries
            .filter { $0.hasSuffix(".ipa") || $0.hasSuffix(".pkg") }
            .map { (directory as NSString).appendingPathComponent($0) }
            .sorted()
    }

    private func extractSubmissionID(from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let lower = line.lowercased()
            if lower.contains("submission id") || lower.contains("submissionid") {
                if let range = line.range(
                    of: "[0-9a-fA-F-]{36}", options: .regularExpression,
                ) {
                    return String(line[range])
                }
            }
        }
        return nil
    }
}
