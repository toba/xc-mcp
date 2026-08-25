import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct SetTestTargetApplicationTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_test_target_application",
            description:
                "Set the target application (macro expansion) for a UI test target in a scheme's Test action",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string("Path to the .xcodeproj file"),
                    ]),
                    "scheme_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the scheme to modify"),
                    ]),
                    "target_application": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the application target to use as the host app for UI tests",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("scheme_name"),
                    .string("target_application"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let schemeName = arguments.getString("scheme_name"),
              let targetApplication = arguments.getString("target_application")
        else {
            throw MCPError.invalidParams(
                "project_path, scheme_name, and target_application are required",
            )
        }

        let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)

        let xcodeproj: XcodeProj

        do {
            xcodeproj = try XcodeProj(path: Path(resolvedProjectPath))
        } catch {
            throw try error.asMCPError()
        }

        // Find the app target
        guard let appTarget = xcodeproj.pbxproj.nativeTargets.first(where: {
            $0.name == targetApplication
        }) else {
            return CallTool.Result.text("Target '\(targetApplication)' not found in project")
        }

        // Find the scheme
        guard let schemePath = SchemePathResolver.findScheme(
            named: schemeName, in: resolvedProjectPath,
        ) else {
            return CallTool.Result.text("Scheme '\(schemeName)' not found in project")
        }

        do {
            let scheme = try XCScheme(pathString: schemePath)

            // Build a BuildableReference for the app target
            let productName = appTarget.productName ?? appTarget.name
            let productType = appTarget.productType
            let buildableName: String

            if let productType, productType == .application {
                buildableName = "\(productName).app"
            } else {
                buildableName = productName
            }

            let buildRef = XCScheme.BuildableReference(
                referencedContainer:
                    "container:\(URL(fileURLWithPath: resolvedProjectPath).lastPathComponent)",
                blueprint: appTarget,
                buildableName: buildableName,
                blueprintName: appTarget.name,
            )

            if let testAction = scheme.testAction {
                testAction.macroExpansion = buildRef
            } else {
                let testAction = XCScheme.TestAction(
                    buildConfiguration: scheme.launchAction?.buildConfiguration ?? "Debug",
                    macroExpansion: buildRef,
                )
                scheme.testAction = testAction
            }

            try scheme.write(path: Path(schemePath), override: true)

            return CallTool.Result.text(
                "Set target application to '\(targetApplication)' in scheme '\(schemeName)'")
        } catch {
            throw try error.asMCPError()
        }
    }
}
