import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddPackageProductTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_package_product",
            description:
            "Link an existing Swift Package product to a target. Use when a package is already in the project but its product needs to be added to a different target. Plugin products (build tool / command plugins) are auto-detected from local Package.swift sources and skip the Frameworks build phase; pass kind='plugin' explicitly for remote packages whose source is not on disk.",
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
                        "description": .string(
                            "Name of the target to link the product to",
                        ),
                    ]),
                    "product_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the Swift Package product to link (e.g., 'HTTPTypes', 'Alamofire')",
                        ),
                    ]),
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("auto"), .string("library"), .string("plugin"),
                        ]),
                        "description": .string(
                            "Product kind. 'library' adds the product to the Frameworks build phase. 'plugin' skips the build phase (build-tool and command plugins are auto-discovered by Xcode). 'auto' (default) detects from local Package.swift sources, falling back to 'library'.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_name"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    private enum ProductKind: String {
        case library
        case plugin
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(productName) = arguments["product_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, and product_name are required",
            )
        }

        let kindArg: String?
        if case let .string(k) = arguments["kind"] {
            kindArg = k
        } else {
            kindArg = nil
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the target
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                throw MCPError.invalidParams("Target '\(targetName)' not found in project")
            }

            // Check if this product is already linked to the target
            if let existing = target.packageProductDependencies,
               existing.contains(where: { $0.productName == productName })
            {
                throw MCPError.invalidParams(
                    "Product '\(productName)' is already linked to target '\(targetName)'",
                )
            }

            // Find the package reference that provides this product by checking existing
            // product dependencies across all targets
            let packageRef: XCRemoteSwiftPackageReference? = xcodeproj.pbxproj.nativeTargets
                .lazy
                .compactMap(\.packageProductDependencies)
                .joined()
                .first(where: { $0.productName == productName })
                .flatMap(\.package)

            // Resolve the product kind
            let resolvedKind: ProductKind
            let kindSource: String
            switch kindArg {
            case "library":
                resolvedKind = .library
                kindSource = "explicit"
            case "plugin":
                resolvedKind = .plugin
                kindSource = "explicit"
            case nil, "auto":
                let projectDir = (projectURL.path as NSString).deletingLastPathComponent
                if let detected = Self.detectProductKind(
                    productName: productName, in: xcodeproj, projectDir: projectDir,
                ) {
                    resolvedKind = detected
                    kindSource = "detected"
                } else {
                    resolvedKind = .library
                    kindSource = "default"
                }
            default:
                throw MCPError.invalidParams(
                    "kind must be one of: auto, library, plugin",
                )
            }

            // Create the product dependency
            let productDependency = XCSwiftPackageProductDependency(
                productName: productName,
                package: packageRef,
            )
            xcodeproj.pbxproj.add(object: productDependency)

            if target.packageProductDependencies == nil {
                target.packageProductDependencies = []
            }
            target.packageProductDependencies?.append(productDependency)

            // Plugins are not linked into the Frameworks build phase — Xcode discovers
            // them via packageProductDependencies and runs them during the build.
            if resolvedKind == .library {
                let buildFile = PBXBuildFile(product: productDependency)
                xcodeproj.pbxproj.add(object: buildFile)

                // Find or create the Frameworks build phase
                let frameworksBuildPhase: PBXFrameworksBuildPhase
                if let existingPhase = target.buildPhases.first(
                    where: { $0 is PBXFrameworksBuildPhase },
                ) as? PBXFrameworksBuildPhase {
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
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            var message =
                "Linked \(resolvedKind.rawValue) product '\(productName)' to target '\(targetName)'"
            if resolvedKind == .plugin {
                message += " (skipped Frameworks build phase — \(kindSource))"
            } else if kindSource == "detected" {
                message += " (kind detected from Package.swift)"
            }
            if packageRef == nil {
                message += " (no existing package reference found — product will resolve at build time)"
            }

            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add package product: \(error.localizedDescription)",
            )
        }
    }

    /// Best-effort detection of a product's kind by inspecting local `Package.swift`
    /// sources reachable from the project. Returns `nil` if no matching product
    /// declaration was found (caller falls back to `.library`).
    private static func detectProductKind(
        productName: String, in xcodeproj: XcodeProj, projectDir: String,
    ) -> ProductKind? {
        let fm = FileManager.default
        let projectDirURL = URL(fileURLWithPath: projectDir)
        var packageDirs: [String] = []

        if let project = xcodeproj.pbxproj.rootObject {
            for localPkg in project.localPackages {
                let rel = localPkg.relativePath
                let resolved: String =
                    rel.hasPrefix("/")
                        ? URL(fileURLWithPath: rel).standardizedFileURL.path
                        : projectDirURL.appendingPathComponent(rel).standardizedFileURL.path
                if fm.fileExists(atPath: resolved) {
                    packageDirs.append(resolved)
                }
            }
        }

        // Also look in conventional checkout locations adjacent to the project.
        // Resolved Xcode SourcePackages typically live in DerivedData, but some
        // setups vendor them under `.build/checkouts` or `.swiftpm/checkouts`.
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
                packageDirs.append(path)
            }
        }

        for pkgDir in packageDirs {
            let pkgSwift = pkgDir + "/Package.swift"
            guard let contents = try? String(contentsOfFile: pkgSwift, encoding: .utf8)
            else { continue }
            if let kind = parseProductKind(productName: productName, packageSwift: contents) {
                return kind
            }
        }
        return nil
    }

    /// Parses a `Package.swift` source for a product declaration matching `productName`.
    /// Returns `.plugin` for `.plugin(name: "X", ...)` and `.library` for
    /// `.library(...)` / `.executable(...)`. Returns `nil` if no match.
    private static func parseProductKind(productName: String, packageSwift: String) -> ProductKind? {
        let escaped = NSRegularExpression.escapedPattern(for: productName)
        let patterns: [(String, ProductKind)] = [
            (#"\.plugin\s*\(\s*name:\s*"\#(escaped)""#, .plugin),
            (#"\.library\s*\(\s*name:\s*"\#(escaped)""#, .library),
            (#"\.executable\s*\(\s*name:\s*"\#(escaped)""#, .library),
        ]
        for (pattern, kind) in patterns {
            if packageSwift.range(of: pattern, options: .regularExpression) != nil {
                return kind
            }
        }
        return nil
    }
}
