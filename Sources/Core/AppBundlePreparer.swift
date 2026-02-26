import Logging
import Foundation
import Subprocess

/// Prepares a debug-built macOS app bundle for launch outside Xcode.
///
/// When Xcode builds a project, framework dependencies may exist only in
/// DerivedData's `BUILT_PRODUCTS_DIR` and not be embedded in the app bundle.
/// Xcode sets `DYLD_FRAMEWORK_PATH` at launch time so the dynamic linker
/// finds them, but that variable is stripped by SIP for hardened-runtime apps
/// launched through Launch Services (`/usr/bin/open`).
///
/// This utility works around the problem by:
/// 1. Symlinking non-embedded frameworks/dylibs from the build products
///    directory into the app bundle's `Contents/Frameworks/`
/// 2. Rewriting absolute `/Library/Frameworks/` install names to `@rpath/`
/// 3. Re-signing the modified bundle
public enum AppBundlePreparer {
    private static let logger = Logger(label: "AppBundlePreparer")

    /// Prepares the app bundle at `appPath` so non-embedded frameworks from
    /// `builtProductsDir` can be found at runtime.
    ///
    /// Does nothing if `builtProductsDir` is nil.
    public static func prepare(appPath: String, builtProductsDir: String?) async throws {
        guard let dir = builtProductsDir else { return }

        let fm = FileManager.default
        let frameworksDir = "\(appPath)/Contents/Frameworks"
        try fm.createDirectory(atPath: frameworksDir, withIntermediateDirectories: true)

        // Step 1: Symlink frameworks and dylibs from BUILT_PRODUCTS_DIR
        let builtProductsURL = URL(fileURLWithPath: dir)
        let contents = try fm.contentsOfDirectory(
            at: builtProductsURL, includingPropertiesForKeys: nil,
        )

        var modified = false
        for item in contents where item.pathExtension == "framework" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) { continue }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }
        for item in contents where item.pathExtension == "dylib" {
            let destPath = "\(frameworksDir)/\(item.lastPathComponent)"
            if fm.fileExists(atPath: destPath) { continue }
            try fm.createSymbolicLink(atPath: destPath, withDestinationPath: item.path)
            modified = true
        }

        // Step 2: Rewrite absolute /Library/Frameworks/ install names to @rpath/
        let macOSDir = "\(appPath)/Contents/MacOS"
        if let macOSContents = try? fm.contentsOfDirectory(atPath: macOSDir) {
            for file in macOSContents {
                let filePath = "\(macOSDir)/\(file)"
                modified = try await rewriteAbsoluteInstallNames(at: filePath) || modified
            }
        }

        guard modified else { return }

        // Step 3: Re-sign with the original identity
        try await resignBundle(appPath: appPath)
    }

    /// Infers the build products directory from an app path inside DerivedData.
    ///
    /// If the app is at `.../Build/Products/Debug/MyApp.app`, returns
    /// `.../Build/Products/Debug`. Returns nil if the path doesn't appear
    /// to be inside DerivedData.
    public static func inferBuiltProductsDir(fromAppPath appPath: String) -> String? {
        let parent = URL(fileURLWithPath: appPath).deletingLastPathComponent().path
        // Heuristic: the app is in DerivedData if the path contains /Build/Products/
        if parent.contains("/Build/Products/") {
            return parent
        }
        return nil
    }

    // MARK: - Private

    /// Rewrites absolute `/Library/Frameworks/` references to `@rpath/`.
    private static func rewriteAbsoluteInstallNames(at binaryPath: String) async throws -> Bool {
        let otoolResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/otool"),
            arguments: ["-L", binaryPath],
        )
        guard otoolResult.succeeded else { return false }

        let prefix = "/Library/Frameworks/"
        var changes: [(old: String, new: String)] = []

        for line in otoolResult.stdout.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(prefix) {
                if let parenRange = trimmed.range(of: " (compatibility") {
                    let oldPath = String(trimmed[..<parenRange.lowerBound])
                    let newPath = "@rpath/" + String(oldPath.dropFirst(prefix.count))
                    changes.append((old: oldPath, new: newPath))
                }
            }
        }

        guard !changes.isEmpty else { return false }

        var args: [String] = []
        for change in changes {
            args += ["-change", change.old, change.new]
        }
        args.append(binaryPath)

        let installResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/install_name_tool"),
            arguments: Arguments(args),
        )

        if !installResult.succeeded {
            logger.warning("install_name_tool failed for \(binaryPath): \(installResult.stderr)")
            return false
        }

        return true
    }

    /// Re-signs the app bundle preserving the original signing identity and entitlements.
    private static func resignBundle(appPath: String) async throws {
        // Extract signing identity
        let identityResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-dvvv", appPath],
            mergeStderr: true,
        )

        var signingIdentity = "-"
        for line in identityResult.stdout.components(separatedBy: .newlines)
            where line.hasPrefix("Authority=")
        {
            signingIdentity = String(line.dropFirst("Authority=".count))
            break
        }

        // Extract entitlements
        let extractResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: ["-d", "--entitlements", "-", "--xml", appPath],
        )
        var tempEntitlementsURL: URL?

        if let data = extractResult.stdout.data(using: .utf8), !data.isEmpty {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("debug_entitlements_\(UUID().uuidString).plist")
            try data.write(to: url)
            tempEntitlementsURL = url
        }

        defer {
            if let url = tempEntitlementsURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Re-sign
        var signArgs = ["--force", "--sign", signingIdentity, "--deep"]
        if let url = tempEntitlementsURL {
            signArgs += ["--entitlements", url.path]
        }
        signArgs.append(appPath)

        let signResult = try await ProcessResult.runSubprocess(
            .path("/usr/bin/codesign"),
            arguments: Arguments(signArgs),
        )

        if !signResult.succeeded {
            logger.warning("Re-signing failed: \(signResult.stderr)")
        }
    }
}
