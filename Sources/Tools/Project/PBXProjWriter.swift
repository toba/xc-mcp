import PathKit
import XcodeProj

public enum PBXProjWriter {
    /// Write a pbxproj file.
    ///
    /// XcodeProj 9.10.0+ natively handles both `dstSubfolderSpec` (numeric) and
    /// `dstSubfolder` (Xcode 26 string) on PBXCopyFilesBuildPhase, so no workaround
    /// is needed.
    public static func write(_ xcodeproj: XcodeProj, to path: Path) throws {
        try xcodeproj.writePBXProj(path: path, outputSettings: PBXOutputSettings())
    }
}
