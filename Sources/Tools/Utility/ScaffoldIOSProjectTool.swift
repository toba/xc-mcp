import MCP
import XCMCPCore

public struct ScaffoldIOSProjectTool: Sendable {
    private let scaffolder: ProjectScaffolder

    public init(pathUtility: PathUtility) {
        scaffolder = ProjectScaffolder(platform: .iOS, pathUtility: pathUtility)
    }

    public func tool() -> Tool { scaffolder.tool() }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        try scaffolder.execute(arguments: arguments)
    }
}
