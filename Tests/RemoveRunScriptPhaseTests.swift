import MCP
import PathKit
import Testing
import XCMCPCore
import XcodeProj
import Foundation
@testable import XCMCPTools

struct RemoveRunScriptPhaseTests {
    let tempDir: String
    let pathUtility: PathUtility

    init() {
        tempDir =
            FileManager.default.temporaryDirectory
                .appendingPathComponent("RemoveRunScriptPhaseTests-\(UUID().uuidString)")
                .path
        pathUtility = PathUtility(basePath: tempDir)
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    @Test
    func toolProperties() {
        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)

        #expect(tool.tool().name == "remove_run_script_phase")

        let schema = tool.tool().inputSchema
        if case let .object(schemaDict) = schema {
            if case let .array(required) = schemaDict["required"] {
                #expect(required.count == 3)
                #expect(required.contains(.string("project_path")))
                #expect(required.contains(.string("target_name")))
                #expect(required.contains(.string("phase_name")))
            }
        }
    }

    @Test
    func validateRequiredParameters() throws {
        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)

        #expect(throws: MCPError.self) {
            try tool.execute(arguments: [
                "project_path": .string("test.xcodeproj"),
                "target_name": .string("App"),
            ])
        }
    }

    @Test
    func removesNamedRunScriptPhase() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let shellPhase = PBXShellScriptBuildPhase(
            name: "SwiftLint",
            shellScript: "swiftlint",
        )
        xcodeproj.pbxproj.add(object: shellPhase)
        target.buildPhases.append(shellPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("SwiftLint"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully removed"))
            #expect(message.contains("SwiftLint"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        let updatedTarget = try #require(updated.pbxproj.nativeTargets.first { $0.name == "App" })
        let shellPhases = updatedTarget.buildPhases.compactMap { $0 as? PBXShellScriptBuildPhase }
        #expect(shellPhases.allSatisfy { $0.name != "SwiftLint" })
        #expect(updated.pbxproj.shellScriptBuildPhases.allSatisfy { $0.name != "SwiftLint" })
    }

    @Test
    func removesUnnamedShellScriptPhase() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let xcodeproj = try XcodeProj(path: projectPath)
        let target = try #require(xcodeproj.pbxproj.nativeTargets.first { $0.name == "App" })
        let shellPhase = PBXShellScriptBuildPhase(shellScript: "echo hi")
        xcodeproj.pbxproj.add(object: shellPhase)
        target.buildPhases.append(shellPhase)
        try xcodeproj.writePBXProj(path: projectPath, outputSettings: PBXOutputSettings())

        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("ShellScript"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Successfully removed"))
        } else {
            Issue.record("Expected text result")
        }

        let updated = try XcodeProj(path: projectPath)
        #expect(updated.pbxproj.shellScriptBuildPhases.isEmpty)
    }

    @Test
    func reportsPhaseNotFound() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("NonExistent"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func reportsTargetNotFound() throws {
        let projectPath = Path(tempDir) + "TestProject.xcodeproj"
        try TestProjectHelper.createTestProjectWithTarget(
            name: "TestProject", targetName: "App", at: projectPath,
        )

        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("NonExistent"),
            "phase_name": .string("SwiftLint"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("not found"))
        } else {
            Issue.record("Expected text result")
        }
    }

    @Test
    func refusesToRemoveAmbiguousPhases() throws {
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

        let tool = RemoveRunScriptPhase(pathUtility: pathUtility)
        let result = try tool.execute(arguments: [
            "project_path": .string(projectPath.string),
            "target_name": .string("App"),
            "phase_name": .string("Dup"),
        ])

        if case let .text(message, _, _) = result.content.first {
            #expect(message.contains("Multiple"))
        } else {
            Issue.record("Expected text result")
        }

        // Both phases remain.
        let updated = try XcodeProj(path: projectPath)
        let count = updated.pbxproj.shellScriptBuildPhases.filter { $0.name == "Dup" }.count
        #expect(count == 2)
    }
}
