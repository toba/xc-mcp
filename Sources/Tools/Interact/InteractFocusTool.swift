import AppKit
import ApplicationServices
import Foundation
import MCP
import XCMCPCore

public struct InteractFocusTool: Sendable {
    private let interactRunner: InteractRunner

    public init(interactRunner: InteractRunner) {
        self.interactRunner = interactRunner
    }

    public func tool() -> Tool {
        Tool(
            name: "interact_focus",
            description:
                "Bring a macOS application to the front and optionally focus a specific element. "
                + "Uses NSRunningApplication.activate() to bring the app forward.",
            inputSchema: .object(
                [
                    "type": .string("object"),
                    "properties": .object(
                        InteractRunner.appResolutionSchemaProperties.merging([
                            "element_id": .object([
                                "type": .string("integer"),
                                "description": .string(
                                    "Optional element ID to focus after activating the app."
                                ),
                            ])
                        ]) { _, new in new }
                    ),
                    "required": .array([]),
                ]
            )
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        let pid = try interactRunner.resolveAppFromArguments(arguments)

        // Bring app to front
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw InteractError.appNotFound("PID \(pid)")
        }
        app.activate()

        var result = "Activated \(app.localizedName ?? "PID \(pid)")."

        // Optionally focus a specific element
        if let elementId = arguments.getInt("element_id") {
            try interactRunner.ensureAccessibility()
            guard
                let cached = await InteractSessionManager.shared.getElement(
                    pid: pid, elementId: elementId
                )
            else {
                throw InteractError.elementNotFound(elementId)
            }
            AXUIElementSetAttributeValue(
                cached.element, kAXFocusedAttribute as CFString, true as CFTypeRef
            )
            result += " Focused element \(elementId)."
        }

        return CallTool.Result(content: [.text(result)])
    }
}
