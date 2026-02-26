import MCP
import XCMCPCore
import Foundation
import Subprocess

public struct GetTestAttachmentsTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "get_test_attachments",
            description:
            "Extract test attachments (screenshots, data files) from an .xcresult bundle. Exports attachments and returns structured metadata from the manifest.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "result_bundle_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcresult bundle.",
                        ),
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
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let resultBundlePath = try arguments.getRequiredString("result_bundle_path")
        let testId = arguments.getString("test_id")
        let outputPath = arguments.getString("output_path")
        let onlyFailures = arguments.getBool("only_failures")

        // Validate the bundle exists
        guard FileManager.default.fileExists(atPath: resultBundlePath) else {
            throw MCPError.invalidParams(
                "Result bundle not found at: \(resultBundlePath)",
            )
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
            if isTemporary {
                try? FileManager.default.removeItem(atPath: exportDir)
            }
        }

        // Build xcresulttool arguments
        var args: [String] = [
            "xcresulttool", "export", "attachments",
            "--path", resultBundlePath,
            "--output-path", exportDir,
        ]
        if let testId {
            args.append(contentsOf: ["--test-id", testId])
        }
        if onlyFailures {
            args.append("--only-failures")
        }

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
            return CallTool.Result(content: [.text("No attachments found in the result bundle.")])
        }

        guard let manifest = try? JSONSerialization
            .jsonObject(with: manifestData) as? [[String: Any]]
        else {
            return CallTool.Result(content: [.text("No attachments found in the result bundle.")])
        }

        if manifest.isEmpty {
            return CallTool.Result(content: [.text("No attachments found in the result bundle.")])
        }

        // Parse the nested manifest structure:
        // [{ "testIdentifier": "...", "attachments": [{ "exportedFileName": "...", ... }] }]
        let attachments = Self.flattenManifest(manifest)

        if attachments.isEmpty {
            return CallTool.Result(content: [.text("No attachments found in the result bundle.")])
        }

        let output = Self.formatAttachments(attachments, exportDir: isTemporary ? nil : exportDir)
        return CallTool.Result(content: [.text(output)])
    }

    struct Attachment {
        let testIdentifier: String?
        let exportedFileName: String
        let name: String
        let isAssociatedWithFailure: Bool
        let timestamp: Double?
    }

    static func flattenManifest(_ manifest: [[String: Any]]) -> [Attachment] {
        var result: [Attachment] = []

        for entry in manifest {
            let testIdentifier = entry["testIdentifier"] as? String

            // "attachments" can be a single object or an array of objects
            let attachmentDicts: [[String: Any]]
            if let array = entry["attachments"] as? [[String: Any]] {
                attachmentDicts = array
            } else if let single = entry["attachments"] as? [String: Any] {
                attachmentDicts = [single]
            } else {
                continue
            }

            for att in attachmentDicts {
                let exportedFileName = att["exportedFileName"] as? String ?? "unknown"
                let name = att["suggestedHumanReadableName"] as? String ?? exportedFileName
                let isFailure = att["isAssociatedWithFailure"] as? Bool ?? false
                let timestamp = att["timestamp"] as? Double

                result.append(Attachment(
                    testIdentifier: testIdentifier,
                    exportedFileName: exportedFileName,
                    name: name,
                    isAssociatedWithFailure: isFailure,
                    timestamp: timestamp,
                ))
            }
        }

        return result
    }

    static func formatAttachments(_ attachments: [Attachment], exportDir: String?) -> String {
        var lines: [String] = []
        lines.append("Found \(attachments.count) attachment(s)")
        if let exportDir {
            lines.append("Exported to: \(exportDir)")
        }
        lines.append("")

        for (index, att) in attachments.enumerated() {
            lines.append("[\(index + 1)] \(att.name)")
            lines.append("    File: \(att.exportedFileName)")
            if let testId = att.testIdentifier {
                lines.append("    Test: \(testId)")
            }
            if let timestamp = att.timestamp {
                lines.append("    Timestamp: \(timestamp)")
            }
            if att.isAssociatedWithFailure {
                lines.append("    Associated with failure")
            }
            if let exportDir {
                lines.append("    Path: \(exportDir)/\(att.exportedFileName)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
