import MCP
import Testing
@testable import XCMCPCore
@testable import XCMCPTools

@Suite("GetTestAttachmentsTool Tests")
struct GetTestAttachmentsToolTests {
    @Test("Tool schema has correct name and description")
    func toolSchema() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        #expect(schema.name == "get_test_attachments")
        #expect(schema.description?.contains("attachments") == true)
    }

    @Test("Tool schema includes all expected parameters")
    func toolParameters() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .object(properties) = inputSchema["properties"]
        else {
            Issue.record("Expected object input schema with properties")
            return
        }

        #expect(properties["result_bundle_path"] != nil)
        #expect(properties["test_id"] != nil)
        #expect(properties["output_path"] != nil)
        #expect(properties["only_failures"] != nil)
    }

    @Test("Tool schema requires result_bundle_path")
    func requiredParams() {
        let tool = GetTestAttachmentsTool()
        let schema = tool.tool()

        guard case let .object(inputSchema) = schema.inputSchema,
              case let .array(required) = inputSchema["required"]
        else {
            Issue.record("Expected object input schema with required array")
            return
        }

        #expect(required.contains(.string("result_bundle_path")))
    }

    @Test("Execute with missing result_bundle_path throws invalidParams")
    func missingRequiredParam() async {
        let tool = GetTestAttachmentsTool()
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [:])
        }
    }

    @Test("Execute with nonexistent path throws invalidParams")
    func nonexistentPath() async {
        let tool = GetTestAttachmentsTool()
        await #expect(throws: MCPError.self) {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/nonexistent/path.xcresult"),
            ])
        }
    }

    @Test("flattenManifest parses nested attachments array")
    func flattenManifestArray() {
        let manifest: [[String: Any]] = [
            [
                "testIdentifier": "ThesisUITests/SideNoteTests/testCitationFlow()",
                "attachments": [
                    [
                        "exportedFileName": "screenshot-1.png",
                        "suggestedHumanReadableName": "Citation Screenshot",
                        "isAssociatedWithFailure": false,
                        "timestamp": 1_740_529_200.0,
                    ],
                    [
                        "exportedFileName": "failure-diff.png",
                        "suggestedHumanReadableName": "Failure Diff",
                        "isAssociatedWithFailure": true,
                        "timestamp": 1_740_529_201.0,
                    ],
                ] as [[String: Any]],
            ],
        ]

        let attachments = GetTestAttachmentsTool.flattenManifest(manifest)
        #expect(attachments.count == 2)

        #expect(attachments[0].name == "Citation Screenshot")
        #expect(attachments[0].exportedFileName == "screenshot-1.png")
        #expect(attachments[0].testIdentifier == "ThesisUITests/SideNoteTests/testCitationFlow()")
        #expect(attachments[0].isAssociatedWithFailure == false)
        #expect(attachments[0].timestamp == 1_740_529_200.0)

        #expect(attachments[1].name == "Failure Diff")
        #expect(attachments[1].exportedFileName == "failure-diff.png")
        #expect(attachments[1].isAssociatedWithFailure == true)
    }

    @Test("flattenManifest parses single attachment object")
    func flattenManifestSingleObject() {
        let manifest: [[String: Any]] = [
            [
                "testIdentifier": "Tests/MyTest/testFoo()",
                "attachments": [
                    "exportedFileName": "data.json",
                    "suggestedHumanReadableName": "Response Body",
                    "isAssociatedWithFailure": false,
                ] as [String: Any],
            ],
        ]

        let attachments = GetTestAttachmentsTool.flattenManifest(manifest)
        #expect(attachments.count == 1)
        #expect(attachments[0].name == "Response Body")
        #expect(attachments[0].exportedFileName == "data.json")
        #expect(attachments[0].testIdentifier == "Tests/MyTest/testFoo()")
    }

    @Test("flattenManifest uses exportedFileName when name is missing")
    func flattenManifestFallbackName() {
        let manifest: [[String: Any]] = [
            [
                "testIdentifier": "Tests/MyTest/testBar()",
                "attachments": [
                    [
                        "exportedFileName": "auto-screenshot.png",
                    ] as [String: Any],
                ] as [[String: Any]],
            ],
        ]

        let attachments = GetTestAttachmentsTool.flattenManifest(manifest)
        #expect(attachments.count == 1)
        #expect(attachments[0].name == "auto-screenshot.png")
        #expect(attachments[0].exportedFileName == "auto-screenshot.png")
    }

    @Test("flattenManifest skips entries without attachments")
    func flattenManifestNoAttachments() {
        let manifest: [[String: Any]] = [
            ["testIdentifier": "Tests/MyTest/testEmpty()"],
        ]

        let attachments = GetTestAttachmentsTool.flattenManifest(manifest)
        #expect(attachments.isEmpty)
    }

    @Test("formatAttachments includes export paths when exportDir is provided")
    func formatAttachmentsWithExportDir() {
        let attachments = [
            GetTestAttachmentsTool.Attachment(
                testIdentifier: "Tests/MyTest/testFoo()",
                exportedFileName: "screenshot.png",
                name: "My Screenshot",
                isAssociatedWithFailure: false,
                timestamp: nil,
            ),
        ]

        let output = GetTestAttachmentsTool.formatAttachments(attachments, exportDir: "/tmp/export")
        #expect(output.contains("My Screenshot"))
        #expect(output.contains("screenshot.png"))
        #expect(output.contains("/tmp/export/screenshot.png"))
        #expect(output.contains("Tests/MyTest/testFoo()"))
    }

    @Test("formatAttachments omits paths when exportDir is nil")
    func formatAttachmentsMetadataOnly() {
        let attachments = [
            GetTestAttachmentsTool.Attachment(
                testIdentifier: nil,
                exportedFileName: "data.bin",
                name: "Binary Data",
                isAssociatedWithFailure: true,
                timestamp: 1_740_529_200.0,
            ),
        ]

        let output = GetTestAttachmentsTool.formatAttachments(attachments, exportDir: nil)
        #expect(output.contains("Binary Data"))
        #expect(output.contains("Associated with failure"))
        #expect(!output.contains("Path:"))
    }
}
