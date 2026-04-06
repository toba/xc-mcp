import MCP
import XCMCPCore
import Foundation
import Subprocess

/// Symbolicates memory addresses to function names using `atos`.
///
/// Wraps `xcrun atos` to convert raw memory addresses from crash logs or
/// diagnostics into human-readable `ClassName.method + offset` format.
///
/// ## Example
///
/// ```
/// symbolicate_address(binary: "/path/to/MyApp.app/Contents/MacOS/MyApp",
///                     load_address: "0x100000000",
///                     addresses: ["0x100001234", "0x100005678"])
/// ```
public struct SymbolicateAddressTool: Sendable {
    public init() {}

    public func tool() -> Tool {
        Tool(
            name: "symbolicate_address",
            description:
            "Convert raw memory addresses to symbol names (function/method + offset) using atos. Essential for symbolicating crash logs and diagnosing unsymbolicated crash reports.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "binary": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the binary or dSYM file to symbolicate against.",
                        ),
                    ]),
                    "load_address": .object([
                        "type": .string("string"),
                        "description": .string(
                            "The load address of the binary (hex, e.g., '0x100000000'). Found in crash log 'Binary Images' section.",
                        ),
                    ]),
                    "addresses": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "Memory addresses to symbolicate (hex strings, e.g., ['0x100001234', '0x100005678']).",
                        ),
                    ]),
                    "arch": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("arm64"), .string("arm64e"), .string("x86_64"),
                        ]),
                        "description": .string(
                            "Architecture of the binary. Default: arm64.",
                        ),
                    ]),
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Attach to a running process by PID instead of using a binary file. When set, binary and load_address are not required.",
                        ),
                    ]),
                ]),
                "required": .array([.string("addresses")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let addresses = arguments.getStringArray("addresses")
        guard !addresses.isEmpty else {
            throw MCPError.invalidParams("addresses must contain at least one address")
        }

        let arch = arguments.getString("arch") ?? "arm64"

        var args: [String] = []

        if let pid = arguments.getInt("pid") {
            // Attach to running process
            args.append(contentsOf: ["-p", "\(pid)"])
        } else {
            // Use binary file
            guard let binary = arguments.getString("binary") else {
                throw MCPError.invalidParams("Either binary or pid is required")
            }
            args.append(contentsOf: ["-o", binary])
            args.append(contentsOf: ["-arch", arch])

            if let loadAddress = arguments.getString("load_address") {
                args.append(contentsOf: ["-l", loadAddress])
            }
        }

        args.append(contentsOf: addresses)

        let result = try await ProcessResult.runSubprocess(
            .name("xcrun"),
            arguments: Arguments(["atos"] + args),
            timeout: .seconds(30),
        )

        guard result.succeeded else {
            throw MCPError.internalError(
                "atos failed (exit \(result.exitCode)): \(result.errorOutput)",
            )
        }

        // Format output: pair each address with its symbolicated name
        let symbols = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")

        var output = ""
        for (index, symbol) in symbols.enumerated() {
            let addr = index < addresses.count ? addresses[index] : "?"
            output += "\(addr)  →  \(symbol)\n"
        }

        return CallTool.Result(content: [.text(text: output, annotations: nil, _meta: nil)])
    }
}
