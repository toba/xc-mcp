import Foundation
import PathKit
import RegexBuilder
import XcodeProj

/// Workaround for tuist/XcodeProj#1034: Xcode 26 uses `dstSubfolder` (string)
/// instead of `dstSubfolderSpec` (numeric) in PBXCopyFilesBuildPhase. XcodeProj 9.7.2
/// only recognizes `dstSubfolderSpec`, silently dropping `dstSubfolder` on round-trip.
/// This writer preserves `dstSubfolder` entries by snapshotting them before write
/// and patching them back after.
///
/// Remove this workaround when XcodeProj ships a fix for #1034.
public enum PBXProjWriter {
  /// Write a pbxproj file, preserving `dstSubfolder` entries that XcodeProj would drop.
  public static func write(_ xcodeproj: XcodeProj, to path: Path) throws {
    // 1. Snapshot dstSubfolder entries from existing file on disk
    let pbxprojPath = path + "project.pbxproj"
    let existingEntries: [String: String]  // objectID -> dstSubfolder value
    if pbxprojPath.exists,
      let content = try? String(contentsOfFile: pbxprojPath.string, encoding: .utf8)
    {
      existingEntries = parseDstSubfolderEntries(from: content)
    } else {
      existingEntries = [:]
    }

    // 2. Let XcodeProj write normally
    try xcodeproj.writePBXProj(path: path, outputSettings: PBXOutputSettings())

    // 3. If there were no dstSubfolder entries to preserve, we're done
    guard !existingEntries.isEmpty else { return }

    // 4. Read the written file and patch back any lost dstSubfolder entries
    let written = try String(contentsOfFile: pbxprojPath.string, encoding: .utf8)
    let patched = patchDstSubfolderEntries(in: written, entries: existingEntries)

    // 5. Only rewrite if something changed
    if patched != written {
      try patched.write(toFile: pbxprojPath.string, atomically: true, encoding: .utf8)
    }
  }

  // MARK: - Internal (visible for testing)

  /// Parse `dstSubfolder = <value>;` entries from raw pbxproj text, keyed by object ID.
  ///
  /// Matches blocks like:
  /// ```
  /// 9608E2CE2E930062002D730E /* CopyFiles */ = {
  ///     isa = PBXCopyFilesBuildPhase;
  ///     dstPath = docx;
  ///     dstSubfolder = Resources;
  ///     ...
  /// };
  /// ```
  static func parseDstSubfolderEntries(from content: String) -> [String: String] {
    var entries: [String: String] = [:]

    // Regex: 24-char hex ID, followed by a block containing both
    // isa = PBXCopyFilesBuildPhase and dstSubfolder = <value>;
    // [^}] matches anything except }, including newlines — so this spans the full block.
    // Two patterns handle either field ordering (isa before/after dstSubfolder).
    let isaFirst =
      /([0-9A-F]{24})\s+\/\*[^*]*\*\/\s*=\s*\{[^}]*isa\s*=\s*PBXCopyFilesBuildPhase;[^}]*dstSubfolder\s*=\s*([^;]+);[^}]*\}/
    let dstFirst =
      /([0-9A-F]{24})\s+\/\*[^*]*\*\/\s*=\s*\{[^}]*dstSubfolder\s*=\s*([^;]+);[^}]*isa\s*=\s*PBXCopyFilesBuildPhase;[^}]*\}/

    for match in content.matches(of: isaFirst) {
      let objectID = String(match.output.1)
      let value = match.output.2.trimmingCharacters(in: .whitespaces)
      entries[objectID] = value
    }
    for match in content.matches(of: dstFirst) {
      let objectID = String(match.output.1)
      let value = match.output.2.trimmingCharacters(in: .whitespaces)
      entries[objectID] = value
    }

    return entries
  }

  /// For each object ID that had a `dstSubfolder` and now lacks both `dstSubfolder` and
  /// `dstSubfolderSpec`, insert `dstSubfolder = <value>;` after the `dstPath` line.
  static func patchDstSubfolderEntries(in content: String, entries: [String: String]) -> String {
    var result = content

    for (objectID, value) in entries {
      // Build a regex to find this object's block
      guard
        let blockRegex = try? Regex(
          "\(objectID)\\s+/\\*[^*]*\\*/\\s*=\\s*\\{[^}]*\\}",
        )
      else {
        continue
      }

      guard let blockMatch = result.firstMatch(of: blockRegex) else {
        continue
      }

      let block = String(result[blockMatch.range])

      // Skip if block already has dstSubfolder or dstSubfolderSpec
      if block.contains("dstSubfolder") || block.contains("dstSubfolderSpec") {
        continue
      }

      // Find the dstPath line within this block and insert dstSubfolder after it
      guard
        let dstPathRegex = try? Regex(
          "\(objectID)\\s+/\\*[^*]*\\*/\\s*=\\s*\\{[^}]*?dstPath\\s*=\\s*[^;]*;",
        )
      else {
        continue
      }

      guard let dstPathMatch = result.firstMatch(of: dstPathRegex) else {
        continue
      }

      let insertionPoint = dstPathMatch.range.upperBound
      result.insert(contentsOf: "\n\t\t\tdstSubfolder = \(value);", at: insertionPoint)
    }

    return result
  }
}
