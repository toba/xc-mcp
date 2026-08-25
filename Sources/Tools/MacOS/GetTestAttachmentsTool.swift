import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct GetTestAttachmentsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        .init(
            name: "get_test_attachments",
            description:
                "Extract test attachments (screenshots, data files) from an .xcresult bundle. Exports attachments and returns structured metadata from the manifest.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcresult bundle."),
                    ]),
                    "test_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Filter to a specific test (e.g. 'MyTests/testFoo()'). If omitted, exports all attachments.",
                        ),
                    ]),
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Directory to export attachment files to. If omitted, uses a temporary directory and only returns metadata.",
                        ),
                    ]),
                    "only_failures": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Only export attachments associated with test failures. Defaults to false.",
                        ),
                    ]),
                ]),
                "required": .array([.string("result_bundle_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let resultBundlePath = try arguments.getRequiredString("result_bundle_path")
        let testID = arguments.getString("test_id")
        let outputPath = arguments.getString("output_path")
        let onlyFailures = arguments.getBool("only_failures")

        // Validate the bundle exists
        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            throw MCPError.invalidParams("Result bundle not found at: \(resultBundlePath)")
        }

        // Determine export directory
        let exportDir: String
        let isTemporary: Bool

        if let outputPath {
            exportDir = outputPath
            isTemporary = false
            // Create output directory if needed
            try FileManager.default.createDirectory(
                atPath: exportDir, withIntermediateDirectories: true,
            )
        } else {
            exportDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("xc-mcp-attachments-\(UUID().uuidString)").path
            isTemporary = true
            try FileManager.default.createDirectory(
                atPath: exportDir, withIntermediateDirectories: true,
            )
        }

        defer {
            if isTemporary { try? FileManager.default.removeItem(atPath: exportDir) }
        }

        // Build xcresulttool arguments
        var args: [String] = [
            "xcresulttool", "export", "attachments",
            "--path", resultBundlePath,
            "--output-path", exportDir,
        ]
        if let testID { args.append(contentsOf: ["--test-id", testID]) }
        if onlyFailures { args.append("--only-failures") }

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(args),
            timeout: .seconds(120),
        )

        guard result.succeeded else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPError.internalError(
                "xcresulttool export failed: \(stderr.isEmpty ? result.stdout : stderr)",
            )
        }

        // Read the manifest
        let manifestPath = "\(exportDir)/manifest.json"
        guard FileManager.default.fileExists(atPath: manifestPath),
            let manifestData = FileManager.default.contents(atPath: manifestPath)
        else {
            return CallTool.Result.text("No attachments found in the result bundle.")
        }

        let attachments = Self.flattenManifest(manifestData)

        if attachments.isEmpty {
            return CallTool.Result.text("No attachments found in the result bundle.")
        }

        let output = Self.formatAttachments(attachments, exportDir: isTemporary ? nil : exportDir)
        return CallTool.Result.text(output)
    }

    struct Attachment {
        let testIdentifier: String?
        let exportedFileName: String
        let name: String
        let isAssociatedWithFailure: Bool
        let timestamp: Double?
    }

    /// One attachment in the `xcresulttool export attachments` manifest.
    private struct ManifestAttachment: Decodable {
        let exportedFileName: String?
        let suggestedHumanReadableName: String?
        let isAssociatedWithFailure: Bool?
        let timestamp: Double?
    }

    /// One test's entry in the manifest.
    private struct ManifestEntry: Decodable {
        let testIdentifier: String?
        let attachments: [ManifestAttachment]

        private enum CodingKeys: String, CodingKey { case testIdentifier, attachments }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            testIdentifier = try container.decodeIfPresent(String.self, forKey: .testIdentifier)

            // xcresulttool writes a bare object for a test that produced one attachment
            if let list = try? container.decode([ManifestAttachment].self, forKey: .attachments) {
                attachments = list
            } else if let single = try? container.decode(
                ManifestAttachment.self, forKey: .attachments,
            ) {
                attachments = [single]
            } else {
                attachments = []
            }
        }
    }

    /// Flattens the manifest's per-test entries into one attachment list.
    ///
    /// - Parameter manifestData: The contents of the `manifest.json` the export wrote.
    /// - Returns: Every attachment the manifest names, empty when it names none.
    static func flattenManifest(_ manifestData: Data) -> [Attachment] {
        guard let entries = try? JSONDecoder().decode([ManifestEntry].self, from: manifestData)
        else { return [] }

        return entries.flatMap { entry in
            entry.attachments.map { attachment in
                let exportedFileName = attachment.exportedFileName ?? "unknown"
                return Attachment(
                    testIdentifier: entry.testIdentifier,
                    exportedFileName: exportedFileName,
                    name: attachment.suggestedHumanReadableName ?? exportedFileName,
                    isAssociatedWithFailure: attachment.isAssociatedWithFailure ?? false,
                    timestamp: attachment.timestamp,
                )
            }
        }
    }

    static func formatAttachments(_ attachments: [Attachment], exportDir: String?) -> String {
        var lines: [String] = []
        lines.append("Found \(attachments.count) attachment(s)")
        if let exportDir { lines.append("Exported to: \(exportDir)") }
        lines.append("")

        for (index, att) in attachments.enumerated() {
            lines.append("[\(index + 1)] \(att.name)")
            lines.append("    File: \(att.exportedFileName)")
            if let testID = att.testIdentifier { lines.append("    Test: \(testID)") }
            if let timestamp = att.timestamp { lines.append("    Timestamp: \(timestamp)") }
            if att.isAssociatedWithFailure { lines.append("    Associated with failure") }
            if let exportDir { lines.append("    Path: \(exportDir)/\(att.exportedFileName)") }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
