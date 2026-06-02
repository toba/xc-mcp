import Foundation
import Testing
@testable import XCMCPCore

struct PIFCacheReaderTests {
    @Test
    func `extractGuid finds raw 64-char hex hash`() {
        let guid = "2bace2f0c1ca98ebcd37f9b1dbb86b48cb3942481f4b12fa08e59af2d729e00c"
        #expect(PIFCacheReader.extractGuid(from: guid) == guid)
    }

    @Test
    func `extractGuid pulls hash out of full target-id string`() {
        let guid = "2bace2f0c1ca98ebcd37f9b1dbb86b48cb3942481f4b12fa08e59af2d729e00c"
        let raw = "target-Core-\(guid)-SDKROOT:iphonesimulator:SDK_VARIANT:iphonesimulator"
        #expect(PIFCacheReader.extractGuid(from: raw) == guid)
    }

    @Test
    func `extractGuid returns nil when no hex hash present`() {
        #expect(PIFCacheReader.extractGuid(from: "not a hash") == nil)
    }

    @Test
    func `load surfaces cacheMissing for a project that has never been built`() throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }

        // DerivedData root with a matching directory but no PIFCache subtree.
        let derivedData = temp.appendingPathComponent("DerivedData")
        let project = derivedData.appendingPathComponent("MyApp-abcdef1234")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let reader = PIFCacheReader()
        do {
            _ = try reader.load(
                projectPath: "/tmp/MyApp.xcodeproj",
                userDerivedDataRoot: derivedData.path,
            )
            Issue.record("expected cacheMissing")
        } catch let error as PIFCacheReader.Error {
            if case .cacheMissing = error {
                // expected
            } else {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    @Test
    func `load surfaces derivedDataNotFound when no matching dir exists`() throws {
        let temp = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: temp) }
        let derivedData = temp.appendingPathComponent("DerivedData")
        try FileManager.default.createDirectory(
            at: derivedData, withIntermediateDirectories: true,
        )

        do {
            _ = try PIFCacheReader().load(
                projectPath: "/tmp/Ghost.xcodeproj",
                userDerivedDataRoot: derivedData.path,
            )
            Issue.record("expected derivedDataNotFound")
        } catch let error as PIFCacheReader.Error {
            if case .derivedDataNotFound = error {
                // expected
            } else {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    @Test
    func `load indexes a synthetic PIFCache and surfaces duplicate target guids`() throws {
        let fixture = try TestPIFCacheFixture.makeWithDuplicateCoreTarget()
        defer { try? FileManager.default.removeItem(at: fixture.tempRoot) }

        let index = try PIFCacheReader().load(
            projectPath: "/tmp/Thesis.xcodeproj",
            derivedDataPath: fixture.derivedDataRoot,
        )

        #expect(index.workspaces.count == 1)
        #expect(index.projects.count == 2)
        #expect(index.targets.count == 3)

        let duplicates = index.targetsByGuid.filter { $0.value.count > 1 }
        #expect(duplicates.count == 1)
        #expect(duplicates[fixture.coreGuid]?.count == 2)

        // Each project lists exactly one target ref.
        let projectsByCore = fixture.coreTargetCacheNames.compactMap { name -> [PIFCacheReader.Project]? in
            index.projectsByTargetRef[name]
        }
        #expect(projectsByCore.count == 2)
    }
}

/// Synthetic on-disk PIFCache, used by both the reader tests and the tool tests.
struct TestPIFCacheFixture {
    let tempRoot: URL
    let derivedDataRoot: String
    let coreGuid: String
    let coreTargetCacheNames: [String]
    let projectAGuid: String
    let projectBGuid: String

    static func makeWithDuplicateCoreTarget() throws -> TestPIFCacheFixture {
        let temp = try makeTempDir()
        let derived = temp.appendingPathComponent("Thesis-deadbeef")
        let cache = derived.appendingPathComponent(
            "Build/Intermediates.noindex/XCBuildData/PIFCache",
        )

        let workspace = cache.appendingPathComponent("workspace")
        let project = cache.appendingPathComponent("project")
        let target = cache.appendingPathComponent("target")
        for dir in [workspace, project, target] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let coreGuid = "2bace2f0c1ca98ebcd37f9b1dbb86b48cb3942481f4b12fa08e59af2d729e00c"
        let coreATargetFile = "TARGET@v11_hash=core_a"
        let coreBTargetFile = "TARGET@v11_hash=core_b"
        let appTargetFile = "TARGET@v11_hash=app_one"
        let projectAFile = "PROJECT@v11_hash=projecta"
        let projectBFile = "PROJECT@v11_hash=projectb"
        let workspaceFile = "WORKSPACE@v11_hash=ws"

        let projectAGuid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let projectBGuid = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        // Two distinct target cache files that share the same top-level guid (the duplicate).
        try writeJSON(at: target.appendingPathComponent(coreATargetFile + "-json"), object: [
            "guid": coreGuid,
            "name": "Core",
            "productTypeIdentifier": "com.apple.product-type.framework",
            "productReference": ["name": "Core.framework"],
            "dependencies": [],
        ])
        try writeJSON(at: target.appendingPathComponent(coreBTargetFile + "-json"), object: [
            "guid": coreGuid,
            "name": "Core",
            "productTypeIdentifier": "com.apple.product-type.framework",
            "productReference": ["name": "Core.framework"],
            "dependencies": [],
        ])
        // A consumer target that depends on Core.
        try writeJSON(at: target.appendingPathComponent(appTargetFile + "-json"), object: [
            "guid": "1111111111111111111111111111111111111111111111111111111111111111",
            "name": "ThesisApp",
            "productTypeIdentifier": "com.apple.product-type.application",
            "productReference": ["name": "ThesisApp.app"],
            "dependencies": [["guid": coreGuid, "name": "Core"]],
        ])

        try writeJSON(at: project.appendingPathComponent(projectAFile + "-json"), object: [
            "guid": projectAGuid,
            "projectName": "Thesis",
            "path": "/Users/test/Thesis.xcodeproj",
            "targets": [coreATargetFile, appTargetFile],
        ])
        try writeJSON(at: project.appendingPathComponent(projectBFile + "-json"), object: [
            "guid": projectBGuid,
            "projectName": "ThesisOther",
            "path": "/Users/test/ThesisOther.xcodeproj",
            "targets": [coreBTargetFile],
        ])

        try writeJSON(at: workspace.appendingPathComponent(workspaceFile + "-json"), object: [
            "guid": "ccccccccccccccccccccccccccccccccccccc",
            "name": "Thesis",
            "path": "/Users/test/Thesis.xcworkspace",
            "projects": [projectAFile, projectBFile],
        ])

        return TestPIFCacheFixture(
            tempRoot: temp,
            derivedDataRoot: derived.path,
            coreGuid: coreGuid,
            coreTargetCacheNames: [coreATargetFile, coreBTargetFile],
            projectAGuid: projectAGuid,
            projectBGuid: projectBGuid,
        )
    }
}

private func makeTempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "pif-test-\(UUID().uuidString)",
    )
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeJSON(at url: URL, object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [])
    try data.write(to: url)
}
