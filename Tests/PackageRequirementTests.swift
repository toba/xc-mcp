import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct PackageRequirementTests {
    // MARK: - Parsing

    @Test func `parses from as up to next major`() {
        #expect(PackageRequirement.parse("from: 1.2.0") == .upToNextMajorVersion("1.2.0"))
        #expect(PackageRequirement.parse("upToNextMajor: 1.2.0") == .upToNextMajorVersion("1.2.0"))
    }

    @Test func `parses up to next minor`() {
        #expect(PackageRequirement.parse("upToNextMinor: 1.2.0") == .upToNextMinorVersion("1.2.0"))
    }

    @Test func `parses exact branch and revision`() {
        #expect(PackageRequirement.parse("exact: 1.2.0") == .exact("1.2.0"))
        #expect(PackageRequirement.parse("branch: main") == .branch("main"))
        #expect(PackageRequirement.parse("revision: abc123") == .revision("abc123"))
    }

    @Test func `parses a range in both notations`() {
        #expect(
            PackageRequirement.parse("range: 1.2.0..<2.0.0") == .range(from: "1.2.0", to: "2.0.0"),
        )
        #expect(
            PackageRequirement.parse("range: 1.2.0 - 2.0.0") == .range(from: "1.2.0", to: "2.0.0"),
        )
    }

    @Test func `treats a bare version as exact`() {
        #expect(PackageRequirement.parse("1.2.0") == .exact("1.2.0"))
    }

    // MARK: - Formatting

    @Test func `format round-trips through parse`() {
        let forms = [
            "from: 1.2.0", "upToNextMinor: 1.2.0", "exact: 1.2.0",
            "branch: main", "revision: abc123", "range: 1.2.0..<2.0.0",
        ]
        for form in forms {
            #expect(PackageRequirement.format(PackageRequirement.parse(form)) == form)
        }
    }

    @Test func `versionWindow describes the allowed interval`() {
        #expect(
            PackageRequirement.versionWindow(.upToNextMajorVersion("2.1.0")) == ">= 2.1.0 < 3.0.0",
        )
        #expect(
            PackageRequirement.versionWindow(.upToNextMinorVersion("2.1.0")) == ">= 2.1.0 < 2.2.0",
        )
        #expect(PackageRequirement.versionWindow(.exact("2.1.0")) == "== 2.1.0")
        #expect(PackageRequirement.versionWindow(.branch("main")) == nil)
    }

    // MARK: - Admission

    @Test func `up to next major admits a newer minor but not a newer major`() {
        let requirement = XCRemoteSwiftPackageReference.VersionRequirement
            .upToNextMajorVersion("2.1.0")
        #expect(PackageRequirement.allows(SemanticVersion("2.2.0")!, requirement: requirement))
        #expect(PackageRequirement.allows(SemanticVersion("2.1.0")!, requirement: requirement))
        #expect(!PackageRequirement.allows(SemanticVersion("3.0.0")!, requirement: requirement))
        #expect(!PackageRequirement.allows(SemanticVersion("2.0.9")!, requirement: requirement))
    }

    @Test func `up to next minor admits a newer patch only`() {
        let requirement = XCRemoteSwiftPackageReference.VersionRequirement
            .upToNextMinorVersion("2.1.0")
        #expect(PackageRequirement.allows(SemanticVersion("2.1.4")!, requirement: requirement))
        #expect(!PackageRequirement.allows(SemanticVersion("2.2.0")!, requirement: requirement))
    }

    @Test func `exact admits only its own version`() {
        let requirement = XCRemoteSwiftPackageReference.VersionRequirement.exact("2.1.0")
        #expect(PackageRequirement.allows(SemanticVersion("2.1.0")!, requirement: requirement))
        #expect(!PackageRequirement.allows(SemanticVersion("2.1.1")!, requirement: requirement))
    }

    @Test func `a range admits its half-open interval`() {
        let requirement = XCRemoteSwiftPackageReference.VersionRequirement
            .range(from: "1.0.0", to: "2.0.0")
        #expect(PackageRequirement.allows(SemanticVersion("1.9.9")!, requirement: requirement))
        #expect(!PackageRequirement.allows(SemanticVersion("2.0.0")!, requirement: requirement))
    }

    @Test func `a branch or revision admits no version`() {
        #expect(!PackageRequirement.allows(SemanticVersion("1.0.0")!, requirement: .branch("main")))
        #expect(!PackageRequirement.allows(SemanticVersion("1.0.0")!, requirement: .revision("abc")))
    }
}
