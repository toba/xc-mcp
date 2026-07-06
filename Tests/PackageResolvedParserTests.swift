import Testing
import Foundation
@testable import XCMCPCore

struct PackageResolvedParserTests {
    let parser = PackageResolvedParser()

    // MARK: - Identity normalization

    @Test
    func `Identity strips git suffix and lowercases`() {
        #expect(
            PackageResolvedParser.identity(
                forURL: "https://github.com/Alamofire/Alamofire.git")
                == "alamofire",
        )
        #expect(
            PackageResolvedParser.identity(
                forURL: "https://github.com/apple/swift-collections")
                == "swift-collections",
        )
        #expect(
            PackageResolvedParser.identity(
                forURL: "https://github.com/apple/swift-nio/")
                == "swift-nio",
        )
        #expect(
            PackageResolvedParser.identity(
                forURL: "git@github.com:apple/swift-log.git")
                == "swift-log",
        )
    }

    // MARK: - v2/v3 format

    @Test
    func `Parses v2 pins`() throws {
        let json = """
            {
              "originHash": "abc",
              "pins": [
                {
                  "identity": "swift-argument-parser",
                  "kind": "remoteSourceControl",
                  "location": "https://github.com/apple/swift-argument-parser.git",
                  "state": { "revision": "deadbeef", "version": "1.5.0" }
                },
                {
                  "identity": "swift-collections",
                  "kind": "remoteSourceControl",
                  "location": "https://github.com/apple/swift-collections.git",
                  "state": { "branch": "main", "revision": "cafef00d" }
                }
              ],
              "version": 2
            }
            """
        let pins = try parser.decode(Data(json.utf8))
        #expect(pins.count == 2)

        let argParser = try #require(pins.first { $0.identity == "swift-argument-parser" })
        #expect(argParser.version == "1.5.0")
        #expect(argParser.revision == "deadbeef")
        #expect(argParser.branch == nil)

        let collections = try #require(pins.first { $0.identity == "swift-collections" })
        #expect(collections.branch == "main")
        #expect(collections.version == nil)
    }

    // MARK: - v1 format

    @Test
    func `Parses v1 pins`() throws {
        let json = """
            {
              "object": {
                "pins": [
                  {
                    "package": "Alamofire",
                    "repositoryURL": "https://github.com/Alamofire/Alamofire.git",
                    "state": { "branch": null, "revision": "abc123", "version": "5.9.0" }
                  }
                ]
              },
              "version": 1
            }
            """
        let pins = try parser.decode(Data(json.utf8))
        #expect(pins.count == 1)
        let pin = try #require(pins.first)
        #expect(pin.identity == "alamofire")
        #expect(pin.location == "https://github.com/Alamofire/Alamofire.git")
        #expect(pin.version == "5.9.0")
        #expect(pin.branch == nil)
    }

    // MARK: - Edge cases

    @Test
    func `Empty pins file yields no pins`() throws {
        let v2 = try parser.decode(Data(#"{"pins":[],"version":2}"#.utf8))
        #expect(v2.isEmpty)
        let v1 = try parser.decode(Data(#"{"object":{"pins":[]},"version":1}"#.utf8))
        #expect(v1.isEmpty)
    }

    @Test
    func `Malformed JSON throws`() {
        #expect(throws: PackageResolvedParser.ParseError.self) {
            try parser.decode(Data("not json".utf8))
        }
    }

    @Test
    func `Unrecognized shape throws`() {
        #expect(throws: PackageResolvedParser.ParseError.self) {
            try parser.decode(Data(#"{"version":9}"#.utf8))
        }
    }

    // MARK: - Candidate locations

    @Test
    func `Candidate locations for xcodeproj target the embedded workspace`() {
        let candidates = PackageResolvedParser.candidateLocations(for: "/tmp/App.xcodeproj")
        #expect(candidates.contains(
            "/tmp/App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ),
        )
    }

    @Test
    func `Candidate locations for package root use Package.resolved`() {
        let candidates = PackageResolvedParser.candidateLocations(for: "/tmp/MyPkg")
        #expect(candidates == ["/tmp/MyPkg/Package.resolved"])
    }
}
