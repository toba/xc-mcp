import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
import TobaTesting
@testable import XCMCPTools

/// Covers the object-level splice that keeps a project edit to the blocks it touched.
@Suite(.temporaryDirectory)
struct PBXProjSpliceTests {
    /// Renders a project file with the given sections, in the layout Xcode and XcodeProj write.
    ///
    /// - Parameters:
    ///   - sections: Each section name with its block lines, in file order.
    ///   - objectVersion: The value of the `objectVersion` key.
    private static func document(
        _ sections: [(String, [String])],
        objectVersion: Int = 77,
    ) -> String {
        var lines = [
            "// !$*UTF8*$!",
            "{",
            "\tarchiveVersion = 1;",
            "\tclasses = {",
            "\t};",
            "\tobjectVersion = \(objectVersion);",
            "\tobjects = {",
        ]

        for (name, blocks) in sections {
            lines.append("")
            lines.append("/* Begin \(name) section */")
            lines.append(contentsOf: blocks)
            lines.append("/* End \(name) section */")
        }
        lines.append("\t};")
        lines.append("\trootObject = PPP /* Project object */;")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static let groupBlock = [
        "\t\tGGG = {",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        "\t\t\t);",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]

    private static let groupBlockWithChild = [
        "\t\tGGG = {",
        "\t\t\tisa = PBXGroup;",
        "\t\t\tchildren = (",
        "\t\t\t\tFFB /* b.swift */,",
        "\t\t\t);",
        "\t\t\tsourceTree = \"<group>\";",
        "\t\t};",
    ]

    @Test
    func `keeps the original text of blocks the edit does not change`() throws {
        // The original writes build files on one line. The serializations spread them over
        // several lines, so a full write would change both of them.
        let original = Self.document([
            ("PBXBuildFile", [
                "\t\tAAA /* a.swift in Sources */ = {isa = PBXBuildFile; fileRef = FFA; };",
                "\t\tCCC /* c.swift in Sources */ = {isa = PBXBuildFile; fileRef = FFC; };",
            ]),
            ("PBXGroup", Self.groupBlock),
        ])
        let multiline = { (key: String, file: String) in
            [
                "\t\t\(key) = {",
                "\t\t\tisa = PBXBuildFile;",
                "\t\t\tfileRef = \(file);",
                "\t\t};",
            ]
        }
        let baseline = Self.document([
            ("PBXBuildFile", multiline("AAA", "FFA") + multiline("CCC", "FFC")),
            ("PBXGroup", Self.groupBlock),
        ])
        let updated = Self.document([
            (
                "PBXBuildFile",
                multiline("AAA", "FFA") + multiline("BBB", "FFB") + multiline("CCC", "FFC"),
            ),
            ("PBXGroup", Self.groupBlockWithChild),
        ])

        let spliced = try #require(
            PBXProjSplice.splice(original: original, baseline: baseline, updated: updated),
        )

        let expected = Self.document([
            (
                "PBXBuildFile",
                ["\t\tAAA /* a.swift in Sources */ = {isa = PBXBuildFile; fileRef = FFA; };"]
                    + multiline("BBB", "FFB")
                    + ["\t\tCCC /* c.swift in Sources */ = {isa = PBXBuildFile; fileRef = FFC; };"],
            ),
            ("PBXGroup", Self.groupBlockWithChild),
        ])
        #expect(spliced == expected)
    }

    @Test
    func `drops an emptied section and creates a new one in name order`() throws {
        let buildFile = ["\t\tAAA = {isa = PBXBuildFile; fileRef = FFA; };"]
        let fileReference = ["\t\tFFB = {isa = PBXFileReference; path = b.swift; };"]

        let original = Self.document([("PBXBuildFile", buildFile), ("PBXGroup", Self.groupBlock)])
        let updated = Self.document([
            ("PBXFileReference", fileReference), ("PBXGroup", Self.groupBlock),
        ])

        let spliced = try #require(
            PBXProjSplice.splice(original: original, baseline: original, updated: updated),
        )
        #expect(spliced == updated)
    }

    @Test
    func `appends a new section after the last one`() throws {
        let configurationList = ["\t\tLLL = {isa = XCConfigurationList; };"]
        let original = Self.document([("PBXGroup", Self.groupBlock)])
        let updated = Self.document([
            ("PBXGroup", Self.groupBlock), ("XCConfigurationList", configurationList),
        ])

        let spliced = try #require(
            PBXProjSplice.splice(original: original, baseline: original, updated: updated),
        )
        #expect(spliced == updated)
    }

    @Test
    func `returns the original when the serializations match`() throws {
        let original = Self.document([("PBXGroup", Self.groupBlockWithChild)])
        let baseline = Self.document([("PBXGroup", Self.groupBlock)])

        let spliced = PBXProjSplice.splice(
            original: original, baseline: baseline, updated: baseline,
        )
        #expect(spliced == original)
    }

    @Test
    func `refuses an edit outside the objects dictionary`() {
        let original = Self.document([("PBXGroup", Self.groupBlock)])
        let updated = Self.document([("PBXGroup", Self.groupBlock)], objectVersion: 90)

        #expect(
            PBXProjSplice.splice(original: original, baseline: original, updated: updated) == nil,
        )
    }

    @Test
    func `ignores braces inside strings and comments`() throws {
        let script = [
            "\t\tSSS /* Run { */ = {",
            "\t\t\tisa = PBXShellScriptBuildPhase;",
            "\t\t\tshellScript = \"if true; then { echo \\\"}\\\"; }; fi\";",
            "\t\t};",
        ]
        let original = Self.document([
            ("PBXGroup", Self.groupBlock), ("PBXShellScriptBuildPhase", script),
        ])
        let updated = Self.document([
            ("PBXGroup", Self.groupBlockWithChild), ("PBXShellScriptBuildPhase", script),
        ])

        let spliced = try #require(
            PBXProjSplice.splice(original: original, baseline: original, updated: updated),
        )
        #expect(spliced == updated)
    }

    @Test
    func `writer keeps the formatting of blocks a build setting edit does not touch`() throws {
        let tempDir = TemporaryDirectory.url
        let projectPath = Path(tempDir.path) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        // Quote a value XcodeProj writes bare. The project means the same, but a full write
        // would drop the quotes.
        let pbxprojPath = XcodeProj.pbxprojPath(projectPath).string
        let written = try String(contentsOfFile: pbxprojPath, encoding: .utf8)
        let bare = "defaultConfigurationName = Release;"
        let quoted = "defaultConfigurationName = \"Release\";"
        try #require(written.contains(bare))
        try written.replacing(bare, with: quoted)
            .write(toFile: pbxprojPath, atomically: true, encoding: .utf8)

        let tool = SetBuildSettingTool(pathUtility: PathUtility(basePath: tempDir.path))
        _ = try tool.execute(arguments: [
            "project_path": Value.string(projectPath.string),
            "target_name": Value.string("App"),
            "configuration": Value.string("Debug"),
            "setting_name": Value.string("SWIFT_VERSION"),
            "setting_value": Value.string("6.0"),
        ])

        let result = try String(contentsOfFile: pbxprojPath, encoding: .utf8)
        #expect(result.contains("SWIFT_VERSION = 6.0;"))
        #expect(!result.contains(bare))
        #expect(result.contains(quoted))
    }
}
