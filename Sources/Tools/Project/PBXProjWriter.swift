import PathKit
import XcodeProj

public enum PBXProjWriter {
    /// Write a pbxproj file.
    ///
    /// Includes a workaround for an XcodeProj bug where
    /// `PBXProjEncoder.sortProjectReferences` force-unwraps `PBXFileElement.name`,
    /// crashing when a project reference's file element only has `path` set (e.g. a
    /// self-referencing xcodeproj). We backfill `name` from `path` before writing.
    public static func write(_ xcodeproj: XcodeProj, to path: Path) throws {
        // Workaround: XcodeProj's sortProjectReferences does `lFile.name!` which
        // crashes when a PBXFileReference used as a ProjectRef has no `name`.
        // Backfill name from path so the force-unwrap succeeds.
        if let project = try xcodeproj.pbxproj.rootProject() {
            for refDict in project.projects {
                if let fileElement = refDict["ProjectRef"], fileElement.name == nil {
                    fileElement.name = fileElement.path
                }
            }
        }
        try xcodeproj.writePBXProj(path: path, outputSettings: PBXOutputSettings())
    }
}
