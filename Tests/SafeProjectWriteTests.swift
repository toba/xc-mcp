import Testing
import Foundation
@testable import XCMCPCore

/// Covers the durability/atomicity/concurrency guarantees required of every project-file write.
struct SafeProjectWriteTests {
    /// Creates a fresh temp directory with a seeded file; returns (dir, filePath). Caller cleans
    /// up.
    private func makeSeededFile(
        contents: String = "{ original = true; }\n",
    ) throws -> (dir: URL, path: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("project.pbxproj").path
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return (dir, path)
    }

    @Test
    func `Writes new contents atomically`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let new = "{ updated = true; }\n"
        try SafeProjectWrite.write(Data(new.utf8), to: path, lockIdentifier: dir.path)

        #expect(try String(contentsOfFile: path, encoding: .utf8) == new)
    }

    @Test
    func `Preimage match permits the write`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let preimage = FileManager.default.contents(atPath: path)
        let new = "{ updated = true; }\n"
        try SafeProjectWrite.write(
            Data(new.utf8), to: path, lockIdentifier: dir.path, expectedPreimage: preimage,
        )
        #expect(try String(contentsOfFile: path, encoding: .utf8) == new)
    }

    @Test
    func `Concurrent external edit is refused and file left intact`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Caller's view of the file at "load" time.
        let stalefPreimage = FileManager.default.contents(atPath: path)

        // Another writer commits in the meantime.
        let interloper = "{ interloper = true; }\n"
        try interloper.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: SafeProjectWriteError.self) {
            try SafeProjectWrite.write(
                Data("{ mine = true; }\n".utf8),
                to: path,
                lockIdentifier: dir.path,
                expectedPreimage: stalefPreimage,
            )
        }
        // The interloper's change is preserved, not clobbered.
        #expect(try String(contentsOfFile: path, encoding: .utf8) == interloper)
    }

    @Test
    func `Invalid plist is rejected and original preserved`() throws {
        let original = "{ valid = plist; }\n"
        let (dir, path) = try makeSeededFile(contents: original)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A blatantly malformed plist that plutil -lint will reject.
        let garbage = "this is { not ] a valid (plist"
        #expect(throws: SafeProjectWriteError.self) {
            try SafeProjectWrite.write(Data(garbage.utf8), to: path, lockIdentifier: dir.path)
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == original)
    }

    @Test
    func `Validation can be skipped for non-plist payloads`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        let notAPlist = "not a plist but a deliberate write\n"
        try SafeProjectWrite.write(
            Data(notAPlist.utf8), to: path, lockIdentifier: dir.path, validate: false,
        )
        #expect(try String(contentsOfFile: path, encoding: .utf8) == notAPlist)
    }

    @Test
    func `File permissions are preserved across the atomic swap`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: path)
        try SafeProjectWrite.write(
            Data("{ updated = true; }\n".utf8), to: path, lockIdentifier: dir.path,
        )
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o640)
    }

    @Test
    func `No temp files leak into the project directory`() throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        try SafeProjectWrite.write(
            Data("{ updated = true; }\n".utf8), to: path, lockIdentifier: dir.path,
        )
        // A rejected write must also leave no temp residue.
        try? SafeProjectWrite.write(Data("garbage { ] (".utf8), to: path, lockIdentifier: dir.path)

        let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(entries == ["project.pbxproj"])
    }

    @Test
    func `Concurrent writers serialize without corruption`() async throws {
        let (dir, path) = try makeSeededFile()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 12 concurrent writers, each writing a distinct valid plist. The lock serializes them, so
        // the final file must be exactly one writer's full payload — never an interleaved mix.
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<12 {
                group.addTask {  // sm:ignore requireTaskName
                    let payload =
                        "{ writer = \(i); padding = \"\(String(repeating: "x", count: 500))\"; }\n"
                    try? SafeProjectWrite.write(
                        Data(payload.utf8), to: path, lockIdentifier: dir.path,
                    )
                }
            }
        }

        let final = try String(contentsOfFile: path, encoding: .utf8)
        // Exactly one writer line survived intact and the file is a valid plist.
        #expect(final.hasPrefix("{ writer = "))
        #expect(final.hasSuffix("; }\n"))
        let lintProc = Process()
        lintProc.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        lintProc.arguments = ["-lint", path]
        try lintProc.run()
        lintProc.waitUntilExit()
        #expect(lintProc.terminationStatus == 0)
    }
}
