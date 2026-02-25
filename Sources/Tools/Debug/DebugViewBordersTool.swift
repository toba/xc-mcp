import MCP
import XCMCPCore
import Foundation

public struct DebugViewBordersTool: Sendable {
    private let lldbRunner: LLDBRunner

    public init(lldbRunner: LLDBRunner = LLDBRunner()) {
        self.lldbRunner = lldbRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "debug_view_borders",
            description:
            "Toggle colored borders on all views in a running macOS app's window via LLDB. Process must be stopped (at a breakpoint or via process interrupt). After enabling, resume with debug_continue and use screenshot_mac_window to see the result.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "pid": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Process ID of the debugged process.",
                        ),
                    ]),
                    "bundle_id": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Bundle identifier of the app (uses registered session).",
                        ),
                    ]),
                    "enabled": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to enable or disable view borders.",
                        ),
                    ]),
                    "border_width": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Border width in points. Defaults to 2.0.",
                        ),
                    ]),
                    "color": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Border color: red, green, blue, yellow, cyan, magenta, orange, or white. Defaults to red.",
                        ),
                    ]),
                ]),
                "required": .array([.string("enabled")]),
            ]),
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        var pid = arguments.getInt("pid").map(Int32.init)

        if pid == nil, let bundleId = arguments.getString("bundle_id") {
            pid = await LLDBSessionManager.shared.getPID(bundleId: bundleId)
        }

        guard let targetPID = pid else {
            throw MCPError.invalidParams(
                "Either pid or bundle_id (with active session) is required",
            )
        }

        guard case let .bool(enabled) = arguments["enabled"] else {
            throw MCPError.invalidParams("'enabled' parameter is required")
        }

        let borderWidth =
            arguments.getDouble("border_width")
                ?? arguments.getInt("border_width").map(Double.init)
                ?? 2.0

        let colorName = arguments.getString("color") ?? "red"

        let colorMap: [String: String] = [
            "red": "redColor",
            "green": "greenColor",
            "blue": "blueColor",
            "yellow": "yellowColor",
            "cyan": "cyanColor",
            "magenta": "magentaColor",
            "orange": "orangeColor",
            "white": "whiteColor",
        ]

        guard let nsColorSelector = colorMap[colorName] else {
            throw MCPError.invalidParams(
                "Invalid color '\(colorName)'. Valid colors: \(colorMap.keys.sorted().joined(separator: ", "))",
            )
        }

        do {
            // Expression evaluation fails on crashed processes
            if let warning = await lldbRunner.crashWarning(pid: targetPID) {
                return CallTool.Result(content: [.text(warning)], isError: true)
            }

            let result = try await lldbRunner.toggleViewBorders(
                pid: targetPID,
                enabled: enabled,
                borderWidth: borderWidth,
                nsColorSelector: nsColorSelector,
            )

            let state = enabled ? "enabled" : "disabled"
            let message = "View borders \(state):\n\n\(result.output)"
            return CallTool.Result(content: [.text(message)])
        } catch {
            throw error.asMCPError()
        }
    }
}
