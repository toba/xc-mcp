import Foundation
import Testing
import XCMCPCore

struct PBXProjReferenceAuditTests {
    /// A minimal pbxproj-shaped plist whose `objects` table defines `obj` and references whatever
    /// UUIDs are listed in `references` from a synthetic object.
    private func pbxproj(defining defined: [String], referencing references: [String]) -> Data {
        let refList = references.map { "\t\t\t\t\($0)," }.joined(separator: "\n")
        var objectsBody = ""
        for uuid in defined {
            objectsBody += "\t\t\(uuid) = {isa = PBXGroup; children = (\n\(refList)\n\t\t\t);};\n"
        }
        let text = """
        // !$*UTF8*$!
        {
        \tarchiveVersion = 1;
        \tclasses = {};
        \tobjectVersion = 77;
        \tobjects = {
        \(objectsBody)\t};
        \trootObject = \(defined.first ?? "");
        }
        """
        return Data(text.utf8)
    }

    @Test func `Detects a reference with no defining object`() {
        let real = "A1B2C3D4E5F600112233445F"
        let dangling = "DEADBEEFDEADBEEFDEADBEEF"
        let data = pbxproj(defining: [real], referencing: [real, dangling])
        let result = PBXProjReferenceAudit.danglingReferences(in: data)
        #expect(result == [dangling])
    }

    @Test func `Resolved references are not dangling`() {
        let a = "AAAAAAAAAAAAAAAAAAAAAAAA"
        let b = "BBBBBBBBBBBBBBBBBBBBBBBB"
        let data = pbxproj(defining: [a, b], referencing: [a, b])
        #expect(PBXProjReferenceAudit.danglingReferences(in: data).isEmpty)
    }

    @Test func `Only newly introduced danglers count against a baseline`() {
        let real = "A1B2C3D4E5F600112233445F"
        let preexisting = "0123456789ABCDEF01234567"  // e.g. a cross-project remoteGlobalIDString
        let introduced = "FEDCBA9876543210FEDCBA98"

        let baseline = pbxproj(defining: [real], referencing: [real, preexisting])
        let candidate = pbxproj(defining: [real], referencing: [real, preexisting, introduced])

        // Absolute audit sees both danglers; the baseline diff isolates only the new one.
        #expect(PBXProjReferenceAudit.danglingReferences(in: candidate) == [preexisting, introduced])
        #expect(
            PBXProjReferenceAudit.newDanglingReferences(candidate: candidate, baseline: baseline)
                == [introduced])
    }

    @Test func `Unparseable data fails open`() {
        #expect(PBXProjReferenceAudit.danglingReferences(in: Data("not a plist".utf8)).isEmpty)
    }
}
