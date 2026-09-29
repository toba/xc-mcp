import Testing
import Foundation
@testable import XCMCPCore

struct CodeSignInspectorTests {
    @Test func `hashes a certificate as uppercase SHA-1 hex`() {
        // The FIPS 180 test vector for SHA-1("abc").
        let hash = CodeSignInspector.certificateHash(der: Data("abc".utf8))
        #expect(hash == "A9993E364706816ABA3E25717850C26C9CD0D89D")
    }

    @Test func `finds no leaf certificate on unsigned code`() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unsigned_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(await CodeSignInspector.leafCertificateHash(dir.path) == nil)
    }

    @Test func `parses Team ID and authority from codesign output`() {
        let output = """
            Executable=/Applications/MyApp.app/Contents/MacOS/MyApp
            Identifier=com.example.MyApp
            Authority=Apple Development: Jane Doe (ABC123XYZ)
            Authority=Apple Worldwide Developer Relations Certification Authority
            TeamIdentifier=TEAM123456
            Sealed Resources version=2
            """
        let info = CodeSignInspector.parse(output, path: "/Applications/MyApp.app")
        #expect(info.teamIdentifier == "TEAM123456")
        #expect(info.authority == "Apple Development: Jane Doe (ABC123XYZ)")
        #expect(!info.isAdHoc)
    }

    @Test func `treats not set Team ID as ad-hoc`() {
        let output = """
            Identifier=ZIPFoundation
            TeamIdentifier=not set
            """
        let info = CodeSignInspector.parse(output, path: "/x/ZIPFoundation.framework")
        #expect(info.teamIdentifier == nil)
        #expect(info.isAdHoc)
        #expect(info.authority == nil)
    }

    @Test func `flags ad-hoc framework when app has a real Team ID`() {
        let app = CodeSignInspector.SigningInfo(
            path: "App.app", teamIdentifier: "TEAM123456", authority: "Apple Development",
        )
        let framework = CodeSignInspector.SigningInfo(
            path: "ZIPFoundation.framework", teamIdentifier: nil, authority: nil,
        )
        let result = CodeSignInspector.evaluateConsistency(app: app, frameworks: [framework])
        #expect(result.hasMismatch)
        #expect(result.mismatches.count == 1)

        let warning = result.warning()
        #expect(warning != nil)
        #expect(warning?.contains("ZIPFoundation.framework") == true)
        #expect(warning?.contains("library validation") == true)
    }

    @Test func `does not flag mismatches when app is ad-hoc`() {
        // Ad-hoc apps don't enforce library validation, so a mixed-team bundle still launches.
        let app = CodeSignInspector.SigningInfo(
            path: "App.app", teamIdentifier: nil, authority: nil,
        )
        let framework = CodeSignInspector.SigningInfo(
            path: "Other.framework", teamIdentifier: "TEAM999", authority: nil,
        )
        let result = CodeSignInspector.evaluateConsistency(app: app, frameworks: [framework])
        #expect(!result.hasMismatch)
        #expect(result.warning() == nil)
    }

    @Test func `does not flag frameworks signed with the same Team ID`() {
        let app = CodeSignInspector.SigningInfo(
            path: "App.app", teamIdentifier: "TEAM123456", authority: nil,
        )
        let framework = CodeSignInspector.SigningInfo(
            path: "Shared.framework", teamIdentifier: "TEAM123456", authority: nil,
        )
        let result = CodeSignInspector.evaluateConsistency(app: app, frameworks: [framework])
        #expect(!result.hasMismatch)
        #expect(result.warning() == nil)
    }

    @Test func `flags a framework signed with a different Team ID`() {
        let app = CodeSignInspector.SigningInfo(
            path: "App.app", teamIdentifier: "TEAM_A", authority: nil,
        )
        let frameworks = [
            CodeSignInspector.SigningInfo(
                path: "Ok.framework", teamIdentifier: "TEAM_A", authority: nil),
            CodeSignInspector.SigningInfo(
                path: "Bad.framework", teamIdentifier: "TEAM_B", authority: nil),
        ]
        let result = CodeSignInspector.evaluateConsistency(app: app, frameworks: frameworks)
        #expect(result.mismatches.map(\.path) == ["Bad.framework"])
    }
}
