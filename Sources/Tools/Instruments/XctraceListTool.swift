import MCP
import XCMCPCore
import Foundation

/// Lists available Instruments templates, instruments, or devices.
///
/// This tool queries `xctrace list` to show what profiling templates, instruments, or devices are
/// available on the system.
public struct XctraceListTool: Sendable {
    private let xctraceRunner: XctraceRunner

    public init(xctraceRunner: XctraceRunner = .init()) { self.xctraceRunner = xctraceRunner }

    public func tool() -> Tool {
        .init(
            name: "xctrace_list",
            description:
                "List available Instruments templates, instruments, or devices via xctrace.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("templates"), .string("instruments"), .string("devices"),
                        ]),
                        "description": .string(
                            "What to list: 'templates' for profiling templates, 'instruments' for available instruments, 'devices' for connected devices.",
                        ),
                    ])
                ]),
                "required": .array([.string("kind")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let kind = try arguments.getRequiredString("kind")

        guard ["templates", "instruments", "devices"].contains(kind) else {
            throw MCPError.invalidParams(
                "Invalid kind: \(kind). Use 'templates', 'instruments', or 'devices'.",
            )
        }

        do {
            let result = try await xctraceRunner.list(kind: kind)

            guard result.succeeded else {
                throw MCPError.internalError("xctrace list \(kind) failed: \(result.stderr)")
            }

            let output = result.stdout.isEmpty ? result.stderr : result.stdout
            return CallTool.Result.text(output)
        } catch {
            throw try error.asMCPError()
        }
    }
}
