import Testing
import XCMCPCore

/// Covers the allocation-free identifier scan that replaced a per-line regular expression.
struct PBXProjParsingTests {
    @Test
    func `finds the leading identifier on a build file line`() {
        let line = "\t\t\tA1B2C3D4E5F60718293A4B5C /* Main.swift in Sources */,"
        #expect(
            PBXProjParsing.firstIdentifier(
                in: line, requireUppercase: true)
                == "A1B2C3D4E5F60718293A4B5C")
    }

    @Test
    func `rejects a run shorter than an identifier`() {
        #expect(PBXProjParsing.firstIdentifier(in: "\t\tABCDEF /* Short */,") == nil)
    }

    @Test
    func `returns the first 24 characters of a longer run`() {
        let line = "  0123456789ABCDEF0123456789ABCDEF"
        #expect(PBXProjParsing.firstIdentifier(in: line) == "0123456789ABCDEF01234567")
    }

    @Test
    func `skips a lowercase run when uppercase is required`() {
        let line = "\t\ta1b2c3d4e5f60718293a4b5c /* Main.swift */, A1B2C3D4E5F60718293A4B5D"
        #expect(
            PBXProjParsing.firstIdentifier(
                in: line, requireUppercase: true)
                == "A1B2C3D4E5F60718293A4B5D")
    }

    @Test
    func `a hyphen breaks a run so a UUID is not an identifier`() {
        #expect(PBXProjParsing.firstIdentifier(in: "5A0F1C2E-3D4B-5A6C-7B8D-9E0F1A2B3C4D") == nil)
    }
}
