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
    /// A property list project changes only in the object blocks the edit touched. The rest of
    /// the file keeps the bytes Xcode wrote, so the diff shows the edit and nothing else. See
    /// ``minimalEdit(of:producing:projectName:)``.
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
        try backfillProjectReferenceNames(in: xcodeproj.pbxproj)

        let destination = destinationPath(for: xcodeproj, in: path)
        var data = try serialize(xcodeproj, destination: destination)

        if xcodeproj.projectFormat == .pbxproj,
           let original = expectedPreimage ?? FileManager.default.contents(atPath: destination),
           let minimal = minimalEdit(
               of: original,
               producing: data,
               projectName: try xcodeproj.pbxproj.rootProject()?.name,
           )
        {
            data = minimal
        }

        try SafeProjectWrite.write(
            data,
            to: destination,
            lockIdentifier: path.string,
            expectedPreimage: expectedPreimage,
        )
    }

    /// The original property list bytes with only the changed object blocks replaced, or `nil`
    /// when the splice does not apply.
    ///
    /// The function serializes the original bytes with XcodeProj to get the baseline, and
    /// ``PBXProjSplice`` copies each block that differs between the baseline and `updated` into
    /// the original text. The result must parse and serialize to exactly `updated`. Any other
    /// outcome returns `nil`, and the caller writes `updated` as it is.
    ///
    /// - Parameters:
    ///   - original: The project file bytes before the edit.
    ///   - updated: The XcodeProj serialization of the edited project.
    ///   - projectName: The name of the root project. XcodeProj takes it from the bundle path
    ///     when it loads a project, and some object comments contain it. A graph parsed from data
    ///     has no path, so the name must come from the loaded graph.
    static func minimalEdit(
        of original: Data,
        producing updated: Data,
        projectName: String?,
    ) -> Data? {
        guard let originalText = String(data: original, encoding: .utf8),
              let updatedText = String(data: updated, encoding: .utf8),
              let baseline = try? serializePropertyList(
                  PBXProj(data: original), projectName: projectName,
              ),
              let baselineText = String(data: baseline, encoding: .utf8),
              let spliced = PBXProjSplice.splice(
                  original: originalText, baseline: baselineText, updated: updatedText,
              )
        else { return nil }

        let data = Data(spliced.utf8)
        if data == original { return data }

        guard let check = try? serializePropertyList(
            PBXProj(data: data), projectName: projectName,
        ), check == updated
        else { return nil }
        return data
    }

    /// Serialize a project graph as a property list, with the same settings ``write`` uses.
    private static func serializePropertyList(
        _ pbxproj: PBXProj,
        projectName: String?,
    ) throws -> Data? {
        if let projectName { try pbxproj.rootProject()?.name = projectName }
        try backfillProjectReferenceNames(in: pbxproj)
        return try pbxproj.dataRepresentation(outputSettings: PBXOutputSettings())
    }

    /// Give each project reference a `name`, taken from its `path`.
    ///
    /// XcodeProj's `sortProjectReferences` does `lFile.name!`, which crashes when a
    /// `PBXFileReference` used as a `ProjectRef` has no `name`.
    private static func backfillProjectReferenceNames(in pbxproj: PBXProj) throws {
        guard let project = try pbxproj.rootProject() else { return }

        for refDict in project.projects {
            if let fileElement = refDict["ProjectRef"], fileElement.name == nil {
                fileElement.name = fileElement.path
            }
        }
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
