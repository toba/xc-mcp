import Testing
import Foundation
@testable import XCMCPCore

struct AppBundlePreparerTests {
    /// Creates a `.framework` bundle with a versioned binary of `byteCount` bytes and returns its
    /// path. The caller is responsible for cleanup of `root`.
    private func makeFramework(named name: String, in root: URL, byteCount: Int) throws -> String {
        let fm = FileManager.default
        let framework = root.appendingPathComponent("\(name).framework")
        let versionA = framework.appendingPathComponent("Versions/A")
        try fm.createDirectory(at: versionA, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: framework.appendingPathComponent("Versions/Current").path,
            withDestinationPath: "A",
        )
        try fm.createSymbolicLink(
            atPath: framework.appendingPathComponent(name).path,
            withDestinationPath: "Versions/Current/\(name)",
        )
        let binary = versionA.appendingPathComponent(name)
        try Data(count: byteCount).write(to: binary)
        return framework.path
    }

    @Test func `detects mergeable reexport stub by size delta`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("abp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let embeddedDir = root.appendingPathComponent("embedded")
        let builtDir = root.appendingPathComponent("built")
        try FileManager.default.createDirectory(at: embeddedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: builtDir, withIntermediateDirectories: true)

        // Mirrors the observed Thesis case: 51 KB stub vs ~20 MB full framework.
        let stub = try makeFramework(named: "Core", in: embeddedDir, byteCount: 51_360)
        let full = try makeFramework(named: "Core", in: builtDir, byteCount: 20_659_984)

        #expect(try AppBundlePreparer.isMergeableStub(embeddedFramework: stub, fullFramework: full))
    }

    @Test func `does not flag a verbatim embedded framework`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("abp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let embeddedDir = root.appendingPathComponent("embedded")
        let builtDir = root.appendingPathComponent("built")
        try FileManager.default.createDirectory(at: embeddedDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: builtDir, withIntermediateDirectories: true)

        // A non-mergeable framework is copied verbatim, so the sizes match.
        let embedded = try makeFramework(named: "Core", in: embeddedDir, byteCount: 1_000_000)
        let full = try makeFramework(named: "Core", in: builtDir, byteCount: 1_000_000)

        #expect(
            try !AppBundlePreparer.isMergeableStub(
                embeddedFramework: embedded, fullFramework: full,
            ),
        )
    }

    @Test func `resolves versioned framework binary path`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("abp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let framework = try makeFramework(named: "Core", in: root, byteCount: 16)
        let binary = AppBundlePreparer.frameworkBinaryPath(framework)
        #expect(binary == "\(framework)/Versions/Current/Core")
    }

    @Test func `adds disable-library-validation to existing entitlements`() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.security.app-sandbox</key>
            <true/>
        </dict>
        </plist>
        """
        let result = try AppBundlePreparer.entitlementsWithLibraryValidationDisabled(
            from: Data(xml.utf8),
        )
        let plist = try PropertyListSerialization.propertyList(
            from: result, format: nil,
        ) as? [String: Any]

        #expect(plist?["com.apple.security.cs.disable-library-validation"] as? Bool == true)
        // Existing entitlements are preserved.
        #expect(plist?["com.apple.security.app-sandbox"] as? Bool == true)
    }

    @Test func `creates entitlements when bundle has none`() throws {
        let result = try AppBundlePreparer.entitlementsWithLibraryValidationDisabled(
            from: Data(),
        )
        let plist = try PropertyListSerialization.propertyList(
            from: result, format: nil,
        ) as? [String: Any]

        #expect(plist?["com.apple.security.cs.disable-library-validation"] as? Bool == true)
        #expect(plist?.count == 1)
    }

    @Test func `resolves flat framework binary path`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("abp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let framework = root.appendingPathComponent("Flat.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data(count: 16).write(to: framework.appendingPathComponent("Flat"))

        let binary = AppBundlePreparer.frameworkBinaryPath(framework.path)
        #expect(binary == "\(framework.path)/Flat")
    }
}
