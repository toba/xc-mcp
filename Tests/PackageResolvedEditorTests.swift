import Testing
import Foundation
@testable import XCMCPCore

struct PackageResolvedEditorTests {
    private let editor = PackageResolvedEditor()

    /// Writes a pins file into a fresh temporary directory and returns its path.
    private func writePins(_ json: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Package.resolved")
        try Data(json.utf8).write(to: file)
        return file.path
    }

    private static let v3 = """
        {
          "originHash" : "abc123",
          "pins" : [
            {
              "identity" : "toba-web",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/toba/toba-web",
              "state" : { "revision" : "aaa", "version" : "2.1.0" }
            },
            {
              "identity" : "grdb.swift",
              "kind" : "remoteSourceControl",
              "location" : "https://github.com/groue/GRDB.swift",
              "state" : { "revision" : "bbb", "version" : "7.0.0" }
            }
          ],
          "version" : 3
        }
        """

    private static let v1 = """
        {
          "object" : {
            "pins" : [
              {
                "package" : "TobaWeb",
                "repositoryURL" : "https://github.com/toba/toba-web.git",
                "state" : { "revision" : "aaa", "version" : "2.1.0" }
              }
            ]
          },
          "version" : 1
        }
        """

    @Test func `drops one pin and leaves the rest`() throws {
        let path = try writePins(Self.v3)
        let removed = try editor.removePins(fileAt: path, identities: ["toba-web"])
        #expect(removed == ["toba-web"])

        let pins = try PackageResolvedParser().parse(fileAt: path)
        #expect(pins.count == 1)
        #expect(pins.first?.identity == "grdb.swift")
        #expect(pins.first?.version == "7.0.0")
    }

    @Test func `drops every pin when no identity is named`() throws {
        let path = try writePins(Self.v3)
        let removed = try editor.removePins(fileAt: path, identities: nil)
        #expect(removed == ["grdb.swift", "toba-web"])
        #expect(try PackageResolvedParser().parse(fileAt: path).isEmpty)
    }

    @Test func `leaves the file alone when nothing matches`() throws {
        let path = try writePins(Self.v3)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let removed = try editor.removePins(fileAt: path, identities: ["not-a-package"])
        #expect(removed.isEmpty)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    }

    @Test func `drops a pin from a v1 file`() throws {
        let path = try writePins(Self.v1)
        let removed = try editor.removePins(fileAt: path, identities: ["toba-web"])
        #expect(removed == ["toba-web"])
        #expect(try PackageResolvedParser().parse(fileAt: path).isEmpty)
    }

    @Test func `preserves fields outside the pins array`() throws {
        let path = try writePins(Self.v3)
        _ = try editor.removePins(fileAt: path, identities: ["toba-web"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["originHash"] as? String == "abc123")
        #expect(root["version"] as? Int == 3)
    }

    @Test func `reports an unreadable file`() throws {
        #expect(throws: PackageResolvedEditor.EditError.self) {
            try editor.removePins(fileAt: "/nonexistent/Package.resolved", identities: nil)
        }
    }

    @Test func `reports a file with no pins array`() throws {
        let path = try writePins("{ \"version\" : 3 }")
        #expect(throws: PackageResolvedEditor.EditError.self) {
            try editor.removePins(fileAt: path, identities: nil)
        }
    }
}

struct PinsFileBackupTests {
    /// Creates a package root holding the given pins file, and returns the root directory.
    private func makePackageRoot(_ json: String?) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let json {
            try Data(json.utf8).write(to: directory.appendingPathComponent("Package.resolved"))
        }
        return directory.path
    }

    private static let pins = """
        {
          "pins" : [
            {
              "identity" : "toba-web",
              "location" : "https://github.com/toba/toba-web",
              "state" : { "revision" : "aaa", "version" : "2.1.0" }
            }
          ],
          "version" : 3
        }
        """

    @Test func `restores the exact bytes after an edit`() throws {
        let root = try makePackageRoot(Self.pins)
        let file = root + "/Package.resolved"
        let original = try Data(contentsOf: URL(fileURLWithPath: file))

        let backup = PinsFileBackup(container: root)
        _ = try PackageResolvedEditor().removePins(fileAt: file, identities: ["toba-web"])
        #expect(try Data(contentsOf: URL(fileURLWithPath: file)) != original)

        #expect(backup.restore())
        #expect(try Data(contentsOf: URL(fileURLWithPath: file)) == original)
    }

    @Test func `removes a file that did not exist at snapshot time`() throws {
        let root = try makePackageRoot(nil)
        let backup = PinsFileBackup(container: root)

        let file = root + "/Package.resolved"
        try Data(Self.pins.utf8).write(to: URL(fileURLWithPath: file))

        #expect(backup.restore())
        #expect(!FileManager.default.fileExists(atPath: file))
    }

    @Test func `succeeds when nothing existed and nothing was written`() throws {
        let backup = try PinsFileBackup(container: makePackageRoot(nil))
        #expect(backup.restore())
    }
}
