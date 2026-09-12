import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddPackageProductTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_package_product",
            description:
                "Link an existing Swift Package product to a target. Use when a package is already in the project but its product needs to be added to a different target. Plugin products (build tool / command plugins) are auto-detected from local Package.swift sources and skip the Frameworks build phase; pass kind='plugin' explicitly for remote packages whose source is not on disk. Pass package_url or package_path to disambiguate when the product has not yet been linked to any target.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to link the product to"),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Swift Package product to link (e.g., 'HTTPTypes', 'Alamofire')",
                        ),
                    ]),
                    "package_url": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional repository URL of the remote package that provides the product. Use when the product has not yet been linked to any target so the package reference cannot be inferred.",
                        ),
                    ]),
                    "package_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional relative path of a local package that provides the product (matches XCLocalSwiftPackageReference.relativePath).",
                        ),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([.string("auto"), .string("library"), .string("plugin")]),
                        "description": .string(
                            "Product kind. 'library' adds the product to the Frameworks build phase. 'plugin' skips the build phase (build-tool and command plugins are auto-discovered by Xcode). 'auto' (default) detects from local Package.swift sources, falling back to 'library'.",
                        ),
                    ]),
                    "platform_filters": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Optional: platforms the link builds for, e.g. ['macos']. This is Xcode's Platforms column, and it is how a multiplatform target links a macOS-only product. Library products only. Accepted names: macos, ios, maccatalyst, tvos, watchos, xros, visionos, driverkit. Use set_platform_filters to change a product that is already linked.",
                        ),
                        "items": .object(["type": .string("string")]),
                    ]),
                ].merging(SwiftPackageTraits.schemaProperty) { _, new in new }),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    private typealias ProductKind = PackageProductKind

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let productName = arguments.getString("product_name")
        else {
            throw MCPError.invalidParams("project_path, target_name, and product_name are required")
        }

        let kindArg = arguments.getString("kind")

        let platformFilters = try PlatformFilters.requested(in: arguments)

        let packageURLArg = arguments.getString("package_url")

        let packagePathArg = arguments.getString("package_path")

        if packageURLArg != nil, packagePathArg != nil {
            throw MCPError.invalidParams("Specify either package_url or package_path, not both")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let preimage = PBXProjWriter.preimage(of: Path(projectURL.path))
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target
            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else { throw MCPError.invalidParams("Target '\(targetName)' not found in project") }

            // Check if this product is already linked to the target
            if let existing = target.packageProductDependencies,
               existing.contains(where: { $0.productName == productName })
            {
                throw MCPError.invalidParams(
                    "Product '\(productName)' is already linked to target '\(targetName)'",
                )
            }

            let projectDir = (projectURL.path as NSString).deletingLastPathComponent

            let owning = try Self.owningPackage(
                productName: productName,
                packageURL: packageURLArg,
                packagePath: packagePathArg,
                in: xcodeproj,
                projectDir: projectDir,
            )

            // Traits belong to the package reference, not to a single product dependency.
            var traitsNote = ""

            if let traits = SwiftPackageTraits.parse(from: arguments) {
                if let remote = owning.remote {
                    remote.traits = SwiftPackageTraits.stored(traits)
                } else if let local = owning.local {
                    local.traits = SwiftPackageTraits.stored(traits)
                } else {
                    throw MCPError.invalidParams(
                        "traits need a package reference — pass package_url or package_path so the owning package is known",
                    )
                }
                traitsNote = SwiftPackageTraits.changeDescription(traits)
            }

            // Resolve the product kind
            let resolvedKind: ProductKind
            let kindSource: KindSource

            switch kindArg {
                case "library":
                    resolvedKind = .library
                    kindSource = .explicit
                case "plugin":
                    resolvedKind = .plugin
                    kindSource = .explicit
                case nil, "auto":
                    if let detected = Self.detectProductKind(
                        productName: productName, in: xcodeproj, projectDir: projectDir,
                    ) {
                        resolvedKind = detected
                        kindSource = .detected
                    } else {
                        resolvedKind = .library
                        kindSource = .default
                    }
                default: throw MCPError.invalidParams("kind must be one of: auto, library, plugin")
            }

            // A plugin enters no build phase, so it carries no build file to hold the key.
            if resolvedKind == .plugin, !platformFilters.isEmpty {
                throw MCPError.invalidParams(
                    "platform_filters apply to a library product alone. Product '\(productName)' resolved to a plugin (\(kindSource.rawValue)), and a plugin is not linked, so it has no Platforms column.",
                )
            }

            // Create the product dependency
            let productDependency = XCSwiftPackageProductDependency(
                productName: productName,
                package: owning.remote,
            )
            xcodeproj.pbxproj.add(object: productDependency)

            if target.packageProductDependencies == nil { target.packageProductDependencies = [] }
            target.packageProductDependencies?.append(productDependency)

            // Plugins are not linked into the Frameworks build phase — Xcode discovers them via
            // packageProductDependencies and runs them during the build.
            if resolvedKind == .library {
                let buildFile = PBXBuildFile(
                    product: productDependency,
                    platformFilters: platformFilters.isEmpty ? nil : platformFilters,
                )
                xcodeproj.pbxproj.add(object: buildFile)

                // Find or create the Frameworks build phase
                let frameworksBuildPhase: PBXFrameworksBuildPhase

                if let existingPhase = target.buildPhases.first(where: {
                    $0 is PBXFrameworksBuildPhase
                }) as? PBXFrameworksBuildPhase {
                    frameworksBuildPhase = existingPhase
                } else {
                    let newPhase = PBXFrameworksBuildPhase()
                    xcodeproj.pbxproj.add(object: newPhase)
                    target.buildPhases.append(newPhase)
                    frameworksBuildPhase = newPhase
                }

                frameworksBuildPhase.files?.append(buildFile)
            }

            // Save project
            try PBXProjWriter.write(
                xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage)

            var message =
                "Linked \(resolvedKind.rawValue) product '\(productName)' to target '\(targetName)'"

            if !platformFilters.isEmpty {
                message += " with platformFilters \(PlatformFilters.describe(platformFilters))"
            }

            if resolvedKind == .plugin {
                message += " (skipped Frameworks build phase — \(kindSource.rawValue))"
            } else if kindSource == .detected { message += " (kind detected from Package.swift)" }

            message += owning.source.note
            message += traitsNote

            return CallTool.Result.text(message)
        } catch {
            throw try error.asMCPError()
        }
    }

    /// The package reference that owns a product, and how the lookup found it.
    private struct OwningPackage {
        /// Absent for a local package, and absent when nothing matched.
        var remote: XCRemoteSwiftPackageReference?
        /// Set only when `package_path` named one. Traits attach to it.
        var local: XCLocalSwiftPackageReference?
        var source: PackageRefSource
    }

    /// The package reference that owns `productName`
    ///
    /// The lookup runs in priority order. An explicit argument wins, then a dependency another
    /// target already links, then a scan of the local `Package.swift` sources matched back to the
    /// project's `remotePackages` and `localPackages`.
    ///
    /// - Parameters:
    ///   - productName: The product the caller is linking.
    ///   - packageURL: The `package_url` argument, or `nil`.
    ///   - packagePath: The `package_path` argument, or `nil`.
    ///   - xcodeproj: The project to search.
    ///   - projectDir: The directory holding the project, where the manifest scan starts.
    /// - Throws: ``MCPError/invalidParams(_:)`` when an explicit argument names a reference the
    ///   project does not hold.
    private static func owningPackage(
        productName: String,
        packageURL: String?,
        packagePath: String?,
        in xcodeproj: XcodeProj,
        projectDir: String,
    ) throws -> OwningPackage {
        if let packageURL {
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let match = project.remotePackages.first(where: { $0.repositoryURL == packageURL })
            else {
                throw MCPError.invalidParams(
                    "No XCRemoteSwiftPackageReference with repositoryURL '\(packageURL)' found in project",
                )
            }
            return .init(remote: match, source: .packageURL)
        }

        if let packagePath {
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let match = project.localPackages.first(where: { $0.relativePath == packagePath })
            else {
                throw MCPError.invalidParams(
                    "No XCLocalSwiftPackageReference with relativePath '\(packagePath)' found in project",
                )
            }
            // XCSwiftPackageProductDependency.package only accepts an
            // XCRemoteSwiftPackageReference; local packages historically omit the field. Mirror
            // that here.
            return .init(local: match, source: .packagePath)
        }

        if let linked = xcodeproj.pbxproj.nativeTargets.lazy
            .compactMap(\.packageProductDependencies)
            .joined()
            .first(where: { $0.productName == productName })?.package {
            return .init(remote: linked, source: .linkedDependency)
        }

        guard let discovered = discoverPackageReference(
            productName: productName, in: xcodeproj, projectDir: projectDir,
        ) else { return .init(source: .unresolved) }

        let remote: XCRemoteSwiftPackageReference? =
            switch discovered {
                case let .remote(ref): ref
                case .local: nil
            }
        return .init(remote: remote, source: .discovered)
    }

    /// Best-effort detection of a product's kind by inspecting local `Package.swift` sources
    /// reachable from the project. Returns `nil` if no matching product declaration was found
    /// (caller falls back to `.library`).
    private static func detectProductKind(
        productName: String,
        in xcodeproj: XcodeProj,
        projectDir: String,
    ) -> ProductKind? {
        for candidate in candidatePackageDirs(in: xcodeproj, projectDir: projectDir) {
            guard let contents = LocalPackageManifests.read(directory: candidate.path) else {
                continue
            }

            if let kind = LocalPackageManifests.productKind(of: productName, in: contents) {
                return kind
            }
        }
        return nil
    }

    /// Locates the owning package reference for `productName` by scanning candidate `Package.swift`
    /// files on disk and matching the package back to the project's `remotePackages` /
    /// `localPackages` collections.
    private static func discoverPackageReference(
        productName: String,
        in xcodeproj: XcodeProj,
        projectDir: String,
    ) -> Discovery? {
        guard let project = xcodeproj.pbxproj.rootObject else { return nil }

        for candidate in candidatePackageDirs(in: xcodeproj, projectDir: projectDir) {
            guard let contents = LocalPackageManifests.read(directory: candidate.path),
                  LocalPackageManifests.productKind(of: productName, in: contents) != nil
            else { continue }

            // Local package match: candidate originates from project.localPackages
            if candidate.origin == .local {
                // Local packages don't carry an XCRemoteSwiftPackageReference, but discovery still
                // succeeded — caller should leave package nil.
                return .local
            }

            // Remote package match: directory basename typically equals the package name (also the
            // URL's last path component without `.git`).
            let dirName = (candidate.path as NSString).lastPathComponent

            if let remote = project.remotePackages.first(where: { ref in
                guard let url = ref.repositoryURL else { return false }
                return Self.repoLastComponent(url) == dirName
            }) { return .remote(remote) }
        }
        return nil
    }

    /// What a scan of the local `Package.swift` sources matched
    ///
    /// A local package carries no `XCRemoteSwiftPackageReference`, so `local` records a match that
    /// answers no reference.
    private enum Discovery {
        case remote(XCRemoteSwiftPackageReference)
        case local
    }

    /// Where the owning package reference came from.
    private enum PackageRefSource {
        case packageURL, packagePath, linkedDependency, discovered, unresolved

        /// The sentence the result text appends, empty when the source needs no explanation.
        var note: String {
            switch self {
                case .packageURL: " (linked package by package_url)"
                case .packagePath:
                    " (matched local package by package_path; package field omitted per pbxproj convention)"
                case .linkedDependency: ""
                case .discovered: " (matched package reference from local Package.swift)"
                case .unresolved:
                    " (no existing package reference found — pass package_url or package_path to link explicitly)"
            }
        }
    }

    /// How the product kind was decided.
    private enum KindSource: String { case explicit, detected, `default` }

    private struct PackageDirCandidate {
        enum Origin { case local, checkout }
        var path: String
        var origin: Origin
    }

    private static func candidatePackageDirs(
        in xcodeproj: XcodeProj,
        projectDir: String,
    ) -> [PackageDirCandidate] {
        let fm = FileManager.default
        var dirs: [PackageDirCandidate] = LocalPackageManifests
            .directories(in: xcodeproj, projectDir: projectDir)
            .map { .init(path: $0, origin: .local) }

        // Conventional checkout locations adjacent to the project. Resolved Xcode SourcePackages
        // typically live under DerivedData (keyed by an unstable hash so we don't scan it), but
        // vendored setups stash checkouts under one of the directories below.
        let candidateRoots = [
            projectDir + "/.build/checkouts",
            projectDir + "/.swiftpm/checkouts",
            projectDir + "/SourcePackages/checkouts",
        ]

        for root in candidateRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }

            for entry in entries {
                let path = "\(root)/\(entry)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                dirs.append(.init(path: path, origin: .checkout))
            }
        }
        return dirs
    }

    /// Returns the last path component of a git repository URL with a trailing `.git` suffix
    /// removed. Handles HTTPS, SSH, and `scp`-style URLs.
    private static func repoLastComponent(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/") { trimmed.removeLast() }
        let lastSlash = trimmed.lastIndex(where: { $0 == "/" || $0 == ":" })
        let tail = lastSlash.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed
        return tail.hasSuffix(".git") ? String(tail.dropLast(4)) : tail
    }
}
