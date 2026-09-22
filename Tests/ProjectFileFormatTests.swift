import Testing
import Foundation
import TobaTesting
@testable import XCMCPCore

/// Covers the two on-disk project formats: which one a bundle holds, which writer accepts it, and
/// which editor refuses it.
@Suite(.temporaryDirectory)
struct ProjectFileFormatTests {
    /// Creates a `.xcodeproj` bundle holding one project file.
    ///
    /// - Parameters:
    ///   - format: The format the bundle stores its objects in.
    ///   - contents: The bytes of the project file.
    /// - Returns: The absolute path of the bundle.
    private func makeBundle(
        format: ProjectFileFormat,
        contents: String,
    ) throws -> String {
        let bundle = TemporaryDirectory.url.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try contents.write(
            toFile: bundle.appendingPathComponent(format.fileName).path,
            atomically: true,
            encoding: .utf8,
        )
        return bundle.path
    }

    // MARK: - Detection

    @Test func `A bundle holding the property list reports the property list format`() throws {
        let bundle = try makeBundle(format: .propertyList, contents: "{ objects = {}; }\n")

        #expect(PBXProjParsing.format(forProject: bundle) == .propertyList)
        #expect(
            PBXProjParsing.projectFile(forProject: bundle)?.path.hasSuffix(
                "project.pbxproj")
                == true)
    }

    @Test func `A bundle holding the JSON file reports the JSON format`() throws {
        let bundle = try makeBundle(format: .json, contents: "{\n}\n")

        #expect(PBXProjParsing.format(forProject: bundle) == .json)
        #expect(
            PBXProjParsing.projectFile(forProject: bundle)?.path.hasSuffix(
                "project.xcproj")
                == true)
    }

    @Test func `A bundle holding neither file reports no format`() throws {
        let bundle = TemporaryDirectory.url.appendingPathComponent("Empty.xcodeproj")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        #expect(PBXProjParsing.format(forProject: bundle.path) == nil)
    }

    @Test func `A file name maps to the format that uses it`() {
        #expect(
            ProjectFileFormat.format(
                ofFileAt: "/a/Demo.xcodeproj/project.pbxproj")
                == .propertyList)
        #expect(ProjectFileFormat.format(ofFileAt: "/a/Demo.xcodeproj/project.xcproj") == .json)
        #expect(ProjectFileFormat.format(ofFileAt: "/a/Demo.xcodeproj/other.plist") == nil)
    }

    // MARK: - Text editor refusal

    @Test func `Reading a JSON project as text fails with a named error`() throws {
        let bundle = try makeBundle(format: .json, contents: "{\n}\n")

        do {
            _ = try PBXProjTextEditor.read(projectPath: bundle)
            Issue.record("the read should have failed")
        } catch {
            #expect(error.description.contains("project.xcproj"))
        }
    }

    @Test func `Writing property list text over a JSON project is refused`() throws {
        let original = "{\n}\n"
        let bundle = try makeBundle(format: .json, contents: original)

        do {
            try PBXProjTextEditor.write("{ objects = {}; }", projectPath: bundle)
            Issue.record("the write should have failed")
        } catch {
            // The same named error the read reports, not a validation failure over a candidate file
            // the write never produced.
            #expect(error.description.contains("project.xcproj"))
        }

        let jsonPath = "\(bundle)/\(ProjectFileFormat.json.fileName)"
        #expect(try String(contentsOfFile: jsonPath, encoding: .utf8) == original)
        #expect(
            !FileManager.default.fileExists(
                atPath: "\(bundle)/\(ProjectFileFormat.propertyList.fileName)"))
    }

    @Test func `A bundle with no project file keeps the missing file error`() throws {
        let bundle = TemporaryDirectory.url.appendingPathComponent("Empty.xcodeproj")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        do {
            _ = try PBXProjTextEditor.read(projectPath: bundle.path)
            Issue.record("the read should have failed")
        } catch {
            #expect(error.description.contains("File not found"))
        }
    }

    // MARK: - Durable write

    @Test func `A JSON project accepts JSON5 that plutil would reject`() throws {
        let bundle = try makeBundle(format: .json, contents: "{\n}\n")
        let path = "\(bundle)/\(ProjectFileFormat.json.fileName)"
        // A comment and a trailing comma are JSON5, and `plutil -lint` refuses both.
        let candidate = """
            {
              // the root object
              "rootObject": "Demo",
            }

            """

        try SafeProjectWrite.write(Data(candidate.utf8), to: path, lockIdentifier: bundle)

        #expect(try String(contentsOfFile: path, encoding: .utf8) == candidate)
    }

    @Test func `A JSON project refuses bytes that parse as neither JSON nor JSON5`() throws {
        let original = "{\n}\n"
        let bundle = try makeBundle(format: .json, contents: original)
        let path = "\(bundle)/\(ProjectFileFormat.json.fileName)"

        #expect(throws: SafeProjectWriteError.self) {
            try SafeProjectWrite.write(
                Data("this is { not ] json".utf8), to: path, lockIdentifier: bundle,
            )
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == original)
    }
}

/// Covers the error text helper that keeps an upstream library message readable.
struct DescriptiveMessageTests {
    private enum Bare: Error {
        case missing(path: String)
    }

    private enum Described: Error, CustomStringConvertible {
        case missing(path: String)

        var description: String {
            switch self {
                case let .missing(path): "The project cannot be found at \(path)"
            }
        }
    }

    private enum Localized: Error, LocalizedError {
        case broken

        var errorDescription: String? { "The project is broken" }
    }

    @Test func `A CustomStringConvertible error keeps its own text`() {
        let error: any Error = Described.missing(path: "/tmp/Missing.xcodeproj")

        #expect(error.descriptiveMessage == "The project cannot be found at /tmp/Missing.xcodeproj")
    }

    @Test func `A LocalizedError keeps its error description`() {
        let error: any Error = Localized.broken

        #expect(error.descriptiveMessage == "The project is broken")
    }

    @Test func `An error with no text of its own names its case rather than a code`() {
        let error: any Error = Bare.missing(path: "/tmp/Missing.xcodeproj")

        #expect(error.descriptiveMessage.contains("missing"))
        #expect(!error.descriptiveMessage.contains("error 0"))
    }
}
