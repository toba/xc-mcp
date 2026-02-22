import Foundation

public enum SchemePathResolver {
    /// Returns the full path to a scheme file if it exists in the project's shared or user scheme
    /// directories.
    public static func findScheme(named name: String, in projectPath: String) -> String? {
        let filename = "\(name).xcscheme"
        for dir in schemeDirs(for: projectPath) {
            let path = "\(dir)/\(filename)"
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Returns all scheme directories (shared + user) for the given `.xcodeproj` path.
    public static func schemeDirs(for projectPath: String) -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []

        let sharedDir = "\(projectPath)/xcshareddata/xcschemes"
        if fm.fileExists(atPath: sharedDir) {
            dirs.append(sharedDir)
        }

        let userdataDir = "\(projectPath)/xcuserdata"
        if let userDirs = try? fm.contentsOfDirectory(atPath: userdataDir) {
            for userDir in userDirs {
                let userSchemeDir = "\(userdataDir)/\(userDir)/xcschemes"
                if fm.fileExists(atPath: userSchemeDir) {
                    dirs.append(userSchemeDir)
                }
            }
        }

        return dirs
    }
}
