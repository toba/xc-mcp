import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public enum PBXProjWriter {
    /// Read the raw bytes of the project's `project.pbxproj`, for use as the ``write`` concurrency
    /// guard preimage. Returns `nil` if the file does not yet exist.
    public static func preimage(of xcodeprojPath: Path) -> Data? {
        FileManager.default.contents(atPath: XcodeProj.pbxprojPath(xcodeprojPath).string)
    }

    /// Write a pbxproj file durably via ``SafeProjectWrite`` (atomic + locked + validated +
    /// rolled-back-on-failure).
    ///
    /// Includes a workaround for an XcodeProj bug where `PBXProjEncoder.sortProjectReferences`
    /// force-unwraps `PBXFileElement.name`, crashing when a project reference's file element only
    /// has `path` set (e.g. a self-referencing xcodeproj). We backfill `name` from `path` before
    /// writing.
    ///
    /// - Parameter expectedPreimage: When provided (the bytes read at load via ``preimage(of:)``),
    ///   the write is refused if the file changed in the meantime, preserving the concurrent edit.
    public static func write(
        _ xcodeproj: XcodeProj,
        to path: Path,
        expectedPreimage: Data? = nil,
    ) throws {
        // Workaround: XcodeProj's sortProjectReferences does `lFile.name!` which crashes when a
        // PBXFileReference used as a ProjectRef has no `name`. Backfill name from path so the
        // force-unwrap succeeds.
        if let project = try xcodeproj.pbxproj.rootProject() {
            for refDict in project.projects {
                if let fileElement = refDict["ProjectRef"], fileElement.name == nil {
                    fileElement.name = fileElement.path
                }
            }
        }

        guard let data = try xcodeproj.pbxproj.dataRepresentation(outputSettings:
                PBXOutputSettings())
        else {
            throw SafeProjectWriteError.ioFailed(
                path: XcodeProj.pbxprojPath(path).string,
                detail: "XcodeProj produced no pbxproj data",
            )
        }

        try SafeProjectWrite.write(
            data,
            to: XcodeProj.pbxprojPath(path).string,
            lockIdentifier: path.string,
            expectedPreimage: expectedPreimage,
        )
    }
}
