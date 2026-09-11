import MCP
import XCMCPCore
import Foundation

/// Raises a Swift package's resolved pins to the newest version each requirement allows.
///
/// `swift build` and `swift test` resolve as a side effect, and resolution reuses every pin it
/// finds, so a newly tagged release never arrives on its own. This tool is the package-root
/// counterpart of `resolve_packages`, which needs an Xcode project or workspace path.
///
/// The report names each pin that moved, so a caller does not diff `Package.resolved` itself. A
/// write run reads the pins file before and after and reports the difference. A dry run reads the
/// report SwiftPM prints, because nothing on disk changes.
public struct SwiftPackageUpdateTool: Sendable {
    private let swiftRunner: SwiftRunner
    private let sessionManager: SessionManager
    private let resolvedParser: PackageResolvedParser

    public init(
        swiftRunner: SwiftRunner = .init(),
        sessionManager: SessionManager,
        resolvedParser: PackageResolvedParser = .init(),
    ) {
        self.swiftRunner = swiftRunner
        self.sessionManager = sessionManager
        self.resolvedParser = resolvedParser
    }

    public func tool() -> Tool {
        var properties: [String: Value] = [
            "package_name": .object([
                "type": .string("string"),
                "description": .string(
                    "SwiftPM identity of the one dependency to move, such as 'toba-data'. Omit to "
                        + "update every dependency, which can move many at once.",
                ),
            ]),
            "dry_run": .object([
                "type": .string("boolean"),
                "description": .string(
                    "When true, report the moves and write no pin. Defaults to false.",
                ),
            ]),
            "timeout": .object([
                "type": .string("integer"),
                "description": .string(
                    "Maximum time in seconds for the update. Defaults to 300 (5 minutes).",
                ),
            ]),
        ]
        properties.merge(SwiftPackageToolSchema.packagePath) { current, _ in current }

        return .init(
            name: "swift_package_update",
            description: "Raise a Swift package's resolved pins with swift package update, so each "
                + "dependency moves to the newest version its requirement allows. Name one "
                + "dependency with package_name to keep the move narrow, or omit it to update every "
                + "one. Reports each pin that moved as name, from and to. Use resolve_packages "
                + "instead for an Xcode project or workspace.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array([]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(
        arguments: [String: Value],
        onProgress: (@Sendable (String) -> Void)? = nil,
    ) async throws -> CallTool.Result {
        let packagePath = try await sessionManager.resolvePackagePath(from: arguments)
        let packageName = arguments.getString("package_name")
        let dryRun = arguments.getBool("dry_run")
        let timeout = arguments.resolveTimeout(default: SwiftRunner.defaultTimeout)

        let before = resolvedParser.pinsByIdentity(for: packagePath)
        if let packageName { try Self.validate(packageName, against: before, at: packagePath) }

        await sessionManager.cancelWarmupIfRunning(packagePath: packagePath)

        let start = ContinuousClock.now
        let result: SwiftResult

        do {
            result = try await swiftRunner.update(
                packagePath: packagePath,
                packageName: packageName,
                dryRun: dryRun,
                timeout: timeout,
                onProgress: onProgress,
            )
        } catch {
            throw try error.asMCPError()
        }

        guard result.succeeded else {
            throw MCPError.internalError("swift package update failed:\n\(result.errorOutput)")
        }

        let elapsed = start.duration(to: .now).elapsedDescription

        guard !dryRun else {
            return CallTool.Result.text(Self.dryRunReport(
                PinMove.planned(fromReport: result.output), packageName: packageName,
                packagePath: packagePath, elapsed: elapsed,
            ))
        }

        return CallTool.Result.text(Self.writeReport(
            PinMove.moves(from: before, to: resolvedParser.pinsByIdentity(for: packagePath)),
            packageName: packageName, packagePath: packagePath, elapsed: elapsed,
        ))
    }

    // MARK: - Reports

    /// What a report calls the run's scope.
    ///
    /// - Parameter packageName: The identity the caller named, absent when the run covered every
    ///   one.
    private static func scope(of packageName: String?) -> String {
        packageName ?? "every dependency"
    }

    /// The report for a run that wrote the pins file.
    ///
    /// - Parameters:
    ///   - moves: The pins whose state differs from the reading taken before the run.
    ///   - packageName: The identity the caller named, absent when the run covered every one.
    ///   - packagePath: The package root the run worked in.
    ///   - elapsed: How long the run took.
    static func writeReport(
        _ moves: [PinMove],
        packageName: String?,
        packagePath: String,
        elapsed: String,
    ) -> String {
        var lines = ["Updated \(scope(of: packageName)) at \(packagePath) (\(elapsed))"]
        lines.append(contentsOf: PinMove.lines(
            moves, header: "Pin changes:", whenEmpty: "No pin moved."))

        if moves.isEmpty {
            lines.append(
                packageName.map {
                    "The requirement for \($0) already admits its resolved version, so nothing "
                        + "newer was allowed. Raise the from: floor in Package.swift to move it "
                        + "further."
                }
                    ?? "Every requirement already admits its resolved version. Raise a from: floor "
                    + "in Package.swift to move one further.",
            )
        }
        return lines.joined(separator: "\n")
    }

    /// The report for a run that wrote nothing.
    ///
    /// - Parameters:
    ///   - moves: The pins SwiftPM said it would move.
    ///   - packageName: The identity the caller named, absent when the run covered every one.
    ///   - packagePath: The package root the run worked in.
    ///   - elapsed: How long the run took.
    static func dryRunReport(
        _ moves: [PinMove],
        packageName: String?,
        packagePath: String,
        elapsed: String,
    ) -> String {
        var lines = [
            "Dry run for \(scope(of: packageName)) at \(packagePath) (\(elapsed)). "
                + "Package.resolved was not written."
        ]
        lines.append(contentsOf: PinMove.lines(
            moves, header: "Planned pin changes:", whenEmpty: "No pin would move."))
        if !moves.isEmpty { lines.append("Pass dry_run: false to write them.") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Pins

    /// Refuses a name that matches no pin in the package.
    ///
    /// SwiftPM compares the argument against the identity each pin records, and it pins every
    /// package the name does not match. A misspelled name therefore exits zero and moves nothing,
    /// so the call reads as a successful no-op. The refusal names the identities in the file
    /// instead.
    ///
    /// - Parameters:
    ///   - packageName: The identity the caller named.
    ///   - pins: The pins read before the run, keyed by identity.
    ///   - packagePath: The package root, for the error text.
    /// - Throws: ``MCPError/invalidParams(_:)`` when the file holds pins and none carries the name.
    static func validate(
        _ packageName: String,
        against pins: [String: ResolvedPin],
        at packagePath: String,
    ) throws(MCPError) {
        guard !pins.isEmpty, !pins.keys.contains(packageName.lowercased()) else { return }
        throw MCPError.invalidParams(
            "No dependency '\(packageName)' in \(packagePath)/Package.resolved. The pins file holds: "
                + pins.keys.sorted().joined(separator: ", ")
                + ". Omit package_name to update every dependency.",
        )
    }
}
