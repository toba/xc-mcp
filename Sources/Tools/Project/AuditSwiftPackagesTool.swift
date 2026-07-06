// Dependency-health checks adapted from crleonard/swift-package-audit (MIT License)
// https://github.com/crleonard/swift-package-audit — reimplemented, not a dependency.
import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Read-only audit of an Xcode project's SwiftPM dependency health.
///
/// Cross-references the packages a project *declares* (`XCRemoteSwiftPackageReference`) against
/// what `Package.resolved` actually *pins*, and flags consistency and stability problems:
/// missing/unresolved/stale pins, branch/revision/exact-version pins, and duplicate URL forms.
/// Never mutates the project or the pins file. Offline only — no network calls.
public struct AuditSwiftPackagesTool: Sendable {
    private let pathUtility: PathUtility
    private let resolvedParser: PackageResolvedParser

    public init(pathUtility: PathUtility, resolvedParser: PackageResolvedParser = .init()) {
        self.pathUtility = pathUtility
        self.resolvedParser = resolvedParser
    }

    // MARK: - Findings

    enum Severity: String, Sendable {
        case error, warning, info

        var icon: String {
            switch self {
                case .error: "❌"
                case .warning: "⚠️"
                case .info: "ℹ️"
            }
        }
    }

    enum Rule: String, Sendable {
        case missingPackageResolved
        case unresolvedReference
        case stalePin
        case branchDependency
        case revisionDependency
        case exactVersion
        case duplicateURLForm
        case urlFormMismatch

        var severity: Severity {
            switch self {
                case .missingPackageResolved, .unresolvedReference: .error
                case .stalePin,
                     .branchDependency,
                     .revisionDependency,
                     .exactVersion,
                     .duplicateURLForm: .warning
                case .urlFormMismatch: .info
            }
        }
    }

    struct Finding: Sendable {
        let rule: Rule
        let package: String
        let message: String
    }

    // MARK: - Tool

    public func tool() -> Tool {
        .init(
            name: "audit_swift_packages",
            description:
                "Audit SwiftPM dependency health for an Xcode project. Cross-references declared "
                + "package requirements against Package.resolved pins and flags missing/unresolved/"
                + "stale pins, unstable branch/revision/exact-version pins, and duplicate URL forms. "
                + "Read-only, offline.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ])
                ]),
                "required": .array([.string("project_path")]),
            ]),
            annotations: .readOnly,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"] else {
            throw MCPError.invalidParams("project_path is required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let xcodeproj = try XcodeProj(path: Path(resolvedProjectPath))
            guard let project = try xcodeproj.pbxproj.rootProject() else {
                throw MCPError.internalError("Unable to access project root")
            }

            let declared = declaredPackages(in: project)
            let pins = try loadPins(for: resolvedProjectPath)

            let findings = audit(declared: declared, pins: pins)
            let report = formatReport(
                findings: findings,
                declaredCount: declared.count,
                pinsPresent: pins != nil,
                pinCount: pins?.count ?? 0,
            )
            return CallTool.Result(content: [.text(text: report, annotations: nil, _meta: nil)])
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to audit Swift packages: \(error.localizedDescription)",
            )
        }
    }

    // MARK: - Data collection

    private struct DeclaredPackage {
        let identity: String
        let url: String
        let requirement: XCRemoteSwiftPackageReference.VersionRequirement?
    }

    private func declaredPackages(in project: PBXProject) -> [DeclaredPackage] {
        project.remotePackages.map { pkg in
            let url = pkg.repositoryURL ?? ""
            return DeclaredPackage(
                identity: PackageResolvedParser.identity(forURL: url),
                url: url,
                requirement: pkg.versionRequirement,
            )
        }
    }

    /// Returns pins, or `nil` when no `Package.resolved` exists.
    private func loadPins(for projectPath: String) throws -> [ResolvedPin]? {
        guard let file = resolvedParser.locate(for: projectPath) else { return nil }

        do {
            return try resolvedParser.parse(fileAt: file)
        } catch {
            throw MCPError.internalError("Package.resolved at \(file) is malformed: \(error)")
        }
    }

    // MARK: - Audit

    private func audit(declared: [DeclaredPackage], pins: [ResolvedPin]?) -> [Finding] {
        var findings: [Finding] = []

        // Stability checks on declared requirements.
        for pkg in declared {
            switch pkg.requirement {
                case let .branch(branch):
                    findings.append(.init(
                        rule: .branchDependency, package: pkg.identity,
                        message: "pinned to branch '\(branch)' — unstable, moves with upstream",
                    ))
                case let .revision(revision):
                    findings.append(.init(
                        rule: .revisionDependency, package: pkg.identity,
                        message: "pinned to raw revision '\(revision)' — untagged commit",
                    ))
                case let .exact(version):
                    findings.append(.init(
                        rule: .exactVersion, package: pkg.identity,
                        message:
                            "locked to exact version \(version) — blocks patch/security updates",
                    ))
                default: break
            }
        }

        // Duplicate URL forms: same identity declared under differing URL strings.
        let byIdentity = Dictionary(grouping: declared, by: \.identity)

        for (identity, group) in byIdentity {
            let forms = Set(group.map { normalizeLocation($0.url) })

            if forms.count > 1 {
                let raw = group.map(\.url).sorted().joined(separator: ", ")
                findings.append(.init(
                    rule: .duplicateURLForm, package: identity,
                    message: "declared under multiple URL forms: \(raw)",
                ))
            }
        }

        guard let pins else {
            findings.append(.init(
                rule: .missingPackageResolved, package: "(project)",
                message: "no Package.resolved found — dependency versions are unpinned",
            ))
            return findings.sorted(by: findingOrder)
        }

        let pinsByIdentity = Dictionary(
            pins.map { ($0.identity, $0) }, uniquingKeysWith: { a, _ in a })
        let declaredIdentities = Set(declared.map(\.identity))

        // Unresolved references: declared but not pinned.
        for pkg in declared where pinsByIdentity[pkg.identity] == nil {
            findings.append(.init(
                rule: .unresolvedReference, package: pkg.identity,
                message: "declared in project but absent from Package.resolved — run resolve",
            ))
        }

        // Stale pins: pinned but no longer declared. URL-form mismatches for matched pins.
        for pin in pins {
            if !declaredIdentities.contains(pin.identity) {
                findings.append(.init(
                    rule: .stalePin, package: pin.identity,
                    message: "pinned in Package.resolved but not referenced by the project",
                ))
                continue
            }
            if let pkg = byIdentity[pin.identity]?.first,
               normalizeLocation(pkg.url) != normalizeLocation(pin.location)
            {
                findings.append(.init(
                    rule: .urlFormMismatch, package: pin.identity,
                    message: "project URL '\(pkg.url)' differs from pinned '\(pin.location)'",
                ))
            }
        }

        return findings.sorted(by: findingOrder)
    }

    private func normalizeLocation(_ url: String) -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix(".git") { trimmed.removeLast(4) }
        return trimmed
    }

    private func findingOrder(_ a: Finding, _ b: Finding) -> Bool {
        func rank(_ s: Severity) -> Int {
            switch s { case .error: 0 case .warning: 1 case .info: 2
            }
        }
        return rank(a.rule.severity) != rank(b.rule.severity)
            ? rank(a.rule.severity) < rank(b.rule.severity)
            : a.package < b.package
    }

    // MARK: - Report

    private func formatReport(
        findings: [Finding],
        declaredCount: Int,
        pinsPresent: Bool,
        pinCount: Int,
    ) -> String {
        let pinsSummary = pinsPresent ? "\(pinCount) pin(s)" : "no Package.resolved"
        var lines = ["Swift package audit — \(declaredCount) declared package(s), \(pinsSummary)"]

        if findings.isEmpty {
            lines.append("\n✅ No dependency-health issues found.")
            return lines.joined(separator: "\n")
        }

        let errors = findings.count(where: { $0.rule.severity == .error })
        let warnings = findings.count(where: { $0.rule.severity == .warning })
        let infos = findings.count(where: { $0.rule.severity == .info })
        lines.append("\n\(errors) error(s), \(warnings) warning(s), \(infos) info\n")

        for finding in findings {
            lines.append(
                "\(finding.rule.severity.icon) [\(finding.rule.rawValue)] \(finding.package): "
                    + finding.message,
            )
        }
        return lines.joined(separator: "\n")
    }
}
