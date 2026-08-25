import MCP
import XcodeProj

/// The build configurations one build setting edit applies to
///
/// `set_build_setting` and `remove_build_setting` take the same `target_name` and `configuration`
/// arguments, and they reject the same three cases: an unknown target, a scope with no
/// configuration list, and an unknown configuration name.
struct BuildSettingScope {
    /// The scope named in result text, either `target 'Name'` or `project`.
    let label: String
    /// The configurations the edit touches.
    let configurations: [XCBuildConfiguration]

    /// The outcome of resolving a scope
    enum Resolution {
        case resolved(BuildSettingScope)
        /// The text the tool returns when the arguments name nothing that exists.
        case message(String)
    }

    /// Resolves the target or project scope and the configurations inside it.
    ///
    /// - Parameters:
    ///   - xcodeproj: The loaded project.
    ///   - targetName: The target to edit, or `nil` for project-level settings.
    ///   - configuration: A configuration name, or `All` for every configuration in the scope.
    /// - Returns: The scope, or the text to return to the client.
    static func resolve(
        in xcodeproj: XcodeProj,
        targetName: String?,
        configuration: String,
    ) -> Resolution {
        let configList: XCConfigurationList
        let label: String

        if let targetName {
            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { return .message("Target '\(targetName)' not found in project") }

            guard let list = target.buildConfigurationList else {
                return .message("Target '\(targetName)' has no build configuration list")
            }
            configList = list
            label = "target '\(targetName)'"
        } else {
            guard let project = xcodeproj.pbxproj.rootObject,
                  let list = project.buildConfigurationList
            else { return .message("Project has no build configuration list") }
            configList = list
            label = "project"
        }

        if configuration.lowercased() == "all" {
            return .resolved(BuildSettingScope(
                label: label, configurations: configList.buildConfigurations))
        }

        guard let config = configList.buildConfigurations.first(where: { $0.name == configuration })
        else { return .message("Configuration '\(configuration)' not found for \(label)") }
        return .resolved(BuildSettingScope(label: label, configurations: [config]))
    }
}
