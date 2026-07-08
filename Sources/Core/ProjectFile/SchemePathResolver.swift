import Foundation

public enum SchemePathResolver {
    /// Returns the full path to a scheme file if it exists in the project's shared or user scheme
    /// directories.
    public static func findScheme(named name: String, in projectPath: String) -> String? {
        let filename = "\(name).xcscheme"

        for dir in schemeDirs(for: projectPath) {
            let path = "\(dir)/\(filename)"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Builds a `container:` reference for a file path relative to the project's parent directory.
    ///
    /// Scheme test plan references use `container:<relative-path>` format. This computes the
    /// relative path from the `.xcodeproj` parent directory, falling back to the absolute path if
    /// the file is outside the project tree.
    public static func containerReference(
        for absolutePath: String,
        relativeTo projectPath: String,
    ) -> String {
        let projectDir = URL(fileURLWithPath: projectPath)
            .deletingLastPathComponent().path
        let relativePath: String
        relativePath = absolutePath.hasPrefix(projectDir)
            ? String(absolutePath.dropFirst(projectDir.count + 1))
            : absolutePath
        return "container:\(relativePath)"
    }

    /// Computes the path of `absolutePath` relative to the directory containing `schemePath`.
    ///
    /// Scheme `StoreKitConfigurationFileReference` identifiers are stored as a path relative to the
    /// `.xcscheme` file's own location — e.g. a repo-root `Thesis.storekit` referenced from
    /// `Project.xcodeproj/xcshareddata/xcschemes/Standard.xcscheme` serializes as
    /// `../../../Thesis.storekit`. Falls back to `absolutePath` if the two paths share no common
    /// root (different volumes).
    public static func schemeRelativeIdentifier(
        for absolutePath: String,
        schemePath: String,
    ) -> String {
        let baseComponents = URL(fileURLWithPath: schemePath)
            .deletingLastPathComponent().standardizedFileURL.pathComponents
        let targetComponents = URL(fileURLWithPath: absolutePath)
            .standardizedFileURL.pathComponents

        guard baseComponents.first == targetComponents.first else { return absolutePath }

        var shared = 0

        while shared < baseComponents.count,
              shared < targetComponents.count,
              baseComponents[shared] == targetComponents[shared]
        { shared += 1 }

        let ascend = Array(repeating: "..", count: baseComponents.count - shared)
        let descend = targetComponents[shared...]
        let parts = ascend + descend
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    /// Returns all scheme directories (shared + user) for the given `.xcodeproj` path.
    public static func schemeDirs(for projectPath: String) -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []

        let sharedDir = "\(projectPath)/xcshareddata/xcschemes"
        if fm.fileExists(atPath: sharedDir) { dirs.append(sharedDir) }

        let userdataDir = "\(projectPath)/xcuserdata"

        if let userDirs = try? fm.contentsOfDirectory(atPath: userdataDir) {
            for userDir in userDirs {
                let userSchemeDir = "\(userdataDir)/\(userDir)/xcschemes"
                if fm.fileExists(atPath: userSchemeDir) { dirs.append(userSchemeDir) }
            }
        }

        return dirs
    }
}
