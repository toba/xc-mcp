import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public enum PBXProjWriter {
    /// Read the raw bytes of the project's object file, for use as the ``write`` concurrency guard
    /// preimage. Returns `nil` if the bundle holds no project file yet.
    ///
    /// The bundle decides which file that is. A project written by Xcode 27 stores its objects as
    /// JSON in `project.xcproj`, and reading the property list path there would hand back `nil` and
    /// drop the guard.
    public static func preimage(of xcodeprojPath: Path) -> Data? {
        guard let file = PBXProjParsing.projectFile(forProject: xcodeprojPath.string) else {
            return nil
        }
        return FileManager.default.contents(atPath: file.path)
    }

    /// Write a project file durably via ``SafeProjectWrite`` (atomic + locked + validated +
    /// rolled-back-on-failure).
    ///
    /// The project is written back in the format it was read from, so a JSON project stays JSON
    /// and a property list project stays a property list. Writing the other file would leave the
    /// bundle holding both, and `XcodeProj` then prefers `project.pbxproj` and silently ignores
    /// every later edit to the JSON.
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

        let destination = destinationPath(for: xcodeproj, in: path)
        let data = try serialize(xcodeproj, destination: destination)

        try SafeProjectWrite.write(
            data,
            to: destination,
            lockIdentifier: path.string,
            expectedPreimage: expectedPreimage,
        )
    }

    /// The file the project is written to, chosen by the format it was read from.
    private static func destinationPath(for xcodeproj: XcodeProj, in path: Path) -> String {
        switch xcodeproj.projectFormat {
            case .xcproj: XcodeProj.xcprojPath(path).string
            case .pbxproj: XcodeProj.pbxprojPath(path).string
        }
    }

    /// Serialize the object graph in the format `destination` names.
    private static func serialize(
        _ xcodeproj: XcodeProj,
        destination: String,
    ) throws -> Data {
        guard xcodeproj.projectFormat == .pbxproj else {
            return try xcodeproj.pbxproj.xcprojData()
        }

        guard let data = try xcodeproj.pbxproj.dataRepresentation(outputSettings:
                PBXOutputSettings())
        else {
            throw SafeProjectWriteError.ioFailed(
                path: destination,
                detail: "XcodeProj produced no pbxproj data",
            )
        }
        return data
    }
}
