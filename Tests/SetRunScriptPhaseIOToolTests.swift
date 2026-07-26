import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct SetRunScriptPhaseIOToolTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("SetRunScriptPhaseIOToolTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    /// Creates a test project with a single named run-script phase and returns its path.
    private func makeProjectWithPhase(
        phaseName: String? = "Compress",
        configure: (PBXShellScriptBuildPhase) -> Void = { _ in },
    ) throws -> Path {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let shellPhase = PBXShellScriptBuildPhase(name: phaseName, shellScript: "true")
        configure(shellPhase)
        xcodeproj.pbxproj.add(object: shellPhase)
        target.buildPhases.append(shellPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())
        return projectPath
    }

    private func loadPhase(_ projectPath: Path, named: String) throws -> PBXShellScriptBuildPhase {
        let xcodeproj = try XcodeProj(path: projectPath)
        return try #require(
            xcodeproj.pbxproj.shellScriptBuildPhases.first { ($0.name ?? "ShellScript") == named },
        )
    }

    @Test
    func toolProperties() {
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        #expect(tool.tool().name == "set_run_script_phase_io")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("target_name")))
                #expect(required.contains(.string("phase_name")))
            }
            if case let .object(props) = schemaDict["properties"] {
                #expect(props["input_paths"] != nil)
                #expect(props["output_paths"] != nil)
                #expect(props["input_file_list_paths"] != nil)
                #expect(props["output_file_list_paths"] != nil)
                #expect(props["dependency_file"] != nil)
                #expect(props["always_out_of_date"] != nil)
            }
        }
    }

    @Test
    func validateRequiredParameters() throws {
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "target_name": .string("App"),
            ])
        }
    }

    @Test
    func requiresAtLeastOneField() throws {
        let projectPath = try makeProjectWithPhase()
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string(projectPath.string),
                "target_name": .string("App"),
                "phase_name": .string("Compress"),
            ])
        }
    }

    @Test
    func setsInputsOutputsAndDependencyFile() throws {
        let projectPath = try makeProjectWithPhase()
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Compress"),
            "input_paths": .array([.string("$(SRCROOT)/style.css")]),
            "output_paths": .array([.string("$(DERIVED_FILE_DIR)/style.css.deflate")]),
            "dependency_file": .string("$(DERIVED_FILE_DIR)/compress.d"),
            "always_out_of_date": .bool(false),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Updated"))
        } else {
            Issue.record("Expected text result")
        }

        let phase = try loadPhase(projectPath, named: "Compress")
        #expect(phase.inputPaths == ["$(SRCROOT)/style.css"])
        #expect(phase.outputPaths == ["$(DERIVED_FILE_DIR)/style.css.deflate"])
        #expect(phase.dependencyFile == "$(DERIVED_FILE_DIR)/compress.d")
        #expect(phase.alwaysOutOfDate == false)
    }

    @Test
    func setsFileListPaths() throws {
        let projectPath = try makeProjectWithPhase()
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Compress"),
            "input_file_list_paths": .array([.string("$(SRCROOT)/inputs.xcfilelist")]),
            "output_file_list_paths": .array([.string("$(SRCROOT)/outputs.xcfilelist")]),
        ])

        let phase = try loadPhase(projectPath, named: "Compress")
        #expect(phase.inputFileListPaths == ["$(SRCROOT)/inputs.xcfilelist"])
        #expect(phase.outputFileListPaths == ["$(SRCROOT)/outputs.xcfilelist"])
    }

    @Test
    func onlyModifiesProvidedFields() throws {
        let projectPath = try makeProjectWithPhase { phase in
            phase.inputPaths = ["keep.in"]
            phase.outputPaths = ["keep.out"]
            phase.alwaysOutOfDate = true
        }
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Compress"),
            "output_paths": .array([.string("new.out")]),
        ])

        let phase = try loadPhase(projectPath, named: "Compress")
        #expect(phase.inputPaths == ["keep.in"])          // untouched
        #expect(phase.outputPaths == ["new.out"])         // updated
        #expect(phase.alwaysOutOfDate == true)            // untouched
    }

    @Test
    func clearsFieldsWithEmptyValues() throws {
        let projectPath = try makeProjectWithPhase { phase in
            phase.inputPaths = ["old.in"]
            phase.inputFileListPaths = ["old.xcfilelist"]
            phase.dependencyFile = "old.d"
        }
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Compress"),
            "input_paths": .array([]),
            "input_file_list_paths": .array([]),
            "dependency_file": .string(""),
        ])

        let phase = try loadPhase(projectPath, named: "Compress")
        #expect(phase.inputPaths.isEmpty)
        #expect(phase.inputFileListPaths == nil)
        #expect(phase.dependencyFile == nil)
    }

    @Test
    func matchesUnnamedPhaseAsShellScript() throws {
        let projectPath = try makeProjectWithPhase(phaseName: nil)
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        _ = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("ShellScript"),
            "output_paths": .array([.string("out")]),
        ])

        let phase = try loadPhase(projectPath, named: "ShellScript")
        #expect(phase.outputPaths == ["out"])
    }

    @Test
    func reportsPhaseNotFound() throws {
        let projectPath = try makeProjectWithPhase()
        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Nope"),
            "output_paths": .array([.string("out")]),
        ])
        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func refusesAmbiguousPhases() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )
        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        for _ in 0..<2 {
            let phase = PBXShellScriptBuildPhase(name: "Dup", shellScript: "true")
            xcodeproj.pbxproj.add(object: phase)
            target.buildPhases.append(phase)
        }
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = SetRunScriptPhaseIOTool(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Dup"),
            "output_paths": .array([.string("out")]),
        ])
        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Multiple"))
        } else {
            Issue.record("Expected text result")
        }
    }
}
