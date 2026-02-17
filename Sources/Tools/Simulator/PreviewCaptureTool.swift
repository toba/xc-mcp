import AppKit
import CoreGraphics
import Foundation
import MCP
import PathKit
import ScreenCaptureKit
import XCMCPCore
import XcodeProj

/// Captures a screenshot of a SwiftUI `#Preview` block by building and running
/// a temporary host app on the iOS Simulator.
///
/// This tool extracts the body of a `#Preview` macro from a Swift source file,
/// generates a minimal host app that renders it, injects a temporary target into
/// the project, builds and launches it on a simulator, takes a screenshot, and
/// cleans up the injected target.
public struct PreviewCaptureTool: Sendable {
    private let xcodebuildRunner: XcodebuildRunner
    private let simctlRunner: SimctlRunner
    private let pathUtility: PathUtility
    private let sessionManager: SessionManager

    public init(
        xcodebuildRunner: XcodebuildRunner = XcodebuildRunner(),
        simctlRunner: SimctlRunner = SimctlRunner(),
        pathUtility: PathUtility,
        sessionManager: SessionManager
    ) {
        self.xcodebuildRunner = xcodebuildRunner
        self.simctlRunner = simctlRunner
        self.pathUtility = pathUtility
        self.sessionManager = sessionManager
    }

    public func tool() -> Tool {
        Tool(
            name: "preview_capture",
            description:
                "Capture a screenshot of a SwiftUI #Preview block. Extracts the preview body from a Swift source file, builds a temporary host app that renders it on the iOS Simulator, and returns a screenshot. Cleans up the temporary target afterward.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the Swift source file containing a #Preview block."),
                    ]),
                    "preview_index": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Which preview to capture if the file has multiple #Preview blocks (0-based). Defaults to 0."
                        ),
                    ]),
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file. Uses session default if not specified."),
                    ]),
                    "workspace_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcworkspace file. Uses session default if not specified."
                        ),
                    ]),
                    "simulator": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Simulator UDID or name. Uses session default if not specified."),
                    ]),
                    "configuration": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Build configuration (Debug or Release). Defaults to Debug."),
                    ]),
                    "save_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional path to also save the screenshot PNG to disk."),
                    ]),
                    "render_delay": .object([
                        "type": .string("number"),
                        "description": .string(
                            "Seconds to wait after launch before capturing screenshot. Defaults to 2.0."
                        ),
                    ]),
                ]),
                "required": .array([.string("file_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) async throws -> CallTool.Result {
        // Track state for cleanup
        var injectedTargetName: String?
        var tempDir: String?
        var resolvedProjectPath: String?
        var schemePath: String?
        var xcconfigPath: String?

        do {
            // Step 1: Resolve inputs
            let filePath = try arguments.getRequiredString("file_path")
            let previewIndex = arguments.getInt("preview_index") ?? 0
            let (projectPath, _) = try await sessionManager.resolveBuildPaths(
                from: arguments)
            let simulator: String?
            if let explicitSim = arguments.getString("simulator") {
                simulator = explicitSim
            } else {
                simulator = await sessionManager.simulatorUDID
            }
            let configuration = await sessionManager.resolveConfiguration(from: arguments)
            let savePath = arguments.getString("save_path")
            let renderDelay = arguments.getDouble("render_delay") ?? 2.0

            // We need a project path for target injection
            guard let projPath = projectPath else {
                throw MCPError.invalidParams(
                    "preview_capture requires a project_path (not just a workspace). Set it with set_session_defaults or pass it directly."
                )
            }

            let resolvedPath = try pathUtility.resolvePath(from: projPath)
            resolvedProjectPath = resolvedPath

            // Step 2: Read and parse source file
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)
            let sourceURL = URL(fileURLWithPath: resolvedFilePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let previews = PreviewExtractor.extractPreviewBodies(from: source)

            guard !previews.isEmpty else {
                throw MCPError.invalidParams(
                    "No #Preview blocks found in \(filePath). Check that the file contains a #Preview { ... } macro."
                )
            }

            guard previewIndex >= 0 && previewIndex < previews.count else {
                throw MCPError.invalidParams(
                    "preview_index \(previewIndex) is out of range. File has \(previews.count) preview(s) (0-\(previews.count - 1))."
                )
            }

            let preview = previews[previewIndex]
            let previewBody = preview.body

            // Step 3: Detect source module
            let projectURL = URL(fileURLWithPath: resolvedPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let (sourceTarget, isAppTarget) = findOwningTarget(
                for: resolvedFilePath, in: xcodeproj,
                projectDir: projectURL.deletingLastPathComponent().path
            )

            let moduleName = sourceTarget?.name
            let deploymentTarget = extractDeploymentTarget(from: sourceTarget)

            // Step 4: Generate preview host app
            let uuid = UUID().uuidString.prefix(8)
            let tempDirectory = "/tmp/PreviewHost_\(uuid)"
            tempDir = tempDirectory
            try FileManager.default.createDirectory(
                atPath: tempDirectory, withIntermediateDirectories: true)

            let hostSourcePath = "\(tempDirectory)/PreviewHostApp.swift"
            let hostSource = generateHostSource(
                previewBody: previewBody,
                moduleName: isAppTarget ? nil : moduleName
            )
            try hostSource.write(toFile: hostSourcePath, atomically: true, encoding: .utf8)

            // For app targets: compile the source file directly into the preview host
            // to avoid access control issues with internal/private types.
            // For framework targets: use `import ModuleName` instead, since compiling
            // the source directly fails when it references internal symbols from
            // dependency frameworks that aren't available as source.
            //
            // When including the source file, we must strip its #Preview blocks.
            // The preview body is already inlined in PreviewHostApp.swift, and
            // leaving #Preview macros in the compiled source triggers a Swift
            // compiler crash (infinite recursion in ASTMangler when mangling
            // nested closure types in a different target context).
            var additionalSourcePaths: [String] = []
            if isAppTarget {
                let strippedSource = PreviewExtractor.stripPreviewBlocks(from: source)
                let strippedPath = "\(tempDirectory)/\(sourceURL.lastPathComponent)"
                try strippedSource.write(
                    toFile: strippedPath, atomically: true, encoding: .utf8)
                additionalSourcePaths = [strippedPath]
            }

            // Step 5: Inject temporary target
            let targetName = "_PreviewHost_\(uuid)"
            injectedTargetName = targetName
            let bundleId = "com.preview-host.\(uuid)"

            try injectTarget(
                xcodeproj: xcodeproj,
                projectPath: resolvedPath,
                targetName: targetName,
                bundleId: bundleId,
                hostSourcePath: hostSourcePath,
                additionalSourcePaths: additionalSourcePaths,
                sourceTarget: sourceTarget,
                isAppTarget: isAppTarget,
                deploymentTarget: deploymentTarget
            )

            // Step 6: Determine platform and build
            schemePath = try createTemporaryScheme(
                projectPath: resolvedPath, targetName: targetName)

            // Try iOS Simulator first if a simulator is specified, fall back to macOS
            var isMacOS = false
            var destination: String
            if let sim = simulator {
                destination = "platform=iOS Simulator,id=\(sim)"
            } else {
                destination = "platform=macOS"
                isMacOS = true
            }

            // Debug config avoids Release's _relinkableLibraryClasses linker error
            // (ld 1230.1, Xcode 26, no workaround). ENABLE_DEBUG_DYLIB=NO prevents
            // .debug.dylib generation that crashes on launch with missing symbols.
            // MERGED_BINARY_TYPE=none keeps framework dylibs real (not empty stubs).
            let previewConfig = "Debug"

            let buildArgs = { (dest: String) -> [String] in
                [
                    "-project", resolvedPath,
                    "-scheme", targetName,
                    "-destination", dest,
                    "-configuration", previewConfig,
                    "ONLY_ACTIVE_ARCH=YES",
                    "-skipMacroValidation",
                    "ENABLE_PREVIEWS=NO",
                    "ENABLE_DEBUG_DYLIB=NO",
                    "MERGED_BINARY_TYPE=none",
                    "SKIP_MERGEABLE_LIBRARY_BUNDLE_HOOK=YES",
                    "SWIFT_COMPILATION_MODE=wholemodule",
                    "SWIFT_OPTIMIZATION_LEVEL=-Onone",
                    "build",
                ]
            }

            var buildResult = try await runBuildTolerant(
                arguments: buildArgs(destination), timeout: 300)

            // If iOS Simulator build failed, fall back to macOS
            if !buildResult.succeeded && !isMacOS {
                FileHandle.standardError.write(
                    Data(
                        "[preview_capture] iOS Sim build failed, falling back to macOS. Error: \(buildResult.output.suffix(500))\n"
                            .utf8))
                destination = "platform=macOS"
                isMacOS = true
                buildResult = try await runBuildTolerant(
                    arguments: buildArgs(destination), timeout: 300)
            }

            if !buildResult.succeeded {
                let errorOutput = ErrorExtractor.extractBuildErrors(from: buildResult.output)
                throw MCPError.internalError("Preview build failed:\n\(errorOutput)")
            }

            // Step 7: Find built app and embed missing frameworks
            let appPath = try await findBuiltAppPath(
                projectPath: resolvedPath, targetName: targetName,
                destination: destination, configuration: previewConfig)

            // Ensure all frameworks from the build products dir are embedded
            // in the app bundle. Cross-project references (like GRDB from a
            // sub-xcodeproj) get built but aren't automatically embedded.
            embedMissingFrameworks(appPath: appPath)

            // Step 8-10: Platform-specific install, launch, screenshot, terminate
            let screenshotData: Data

            if isMacOS {
                // macOS: launch the binary directly with DYLD_FRAMEWORK_PATH set
                // so framework dependencies resolve from the build products dir.
                // Using 'open -a' goes through LaunchServices which strips env vars.
                let appURL = URL(fileURLWithPath: appPath)
                let appName = appURL.deletingPathExtension().lastPathComponent
                let execPath = appURL
                    .appendingPathComponent("Contents/MacOS/\(appName)").path
                let buildProductsDir = appURL.deletingLastPathComponent().path

                let launchProcess = Process()
                launchProcess.executableURL = URL(fileURLWithPath: execPath)
                var env = ProcessInfo.processInfo.environment
                env["DYLD_FRAMEWORK_PATH"] = buildProductsDir
                launchProcess.environment = env
                let launchPipe = Pipe()
                launchProcess.standardError = launchPipe
                launchProcess.standardOutput = FileHandle.nullDevice
                // Launch in background — don't wait for exit since it's a GUI app
                try launchProcess.run()

                // Give the app a moment to crash or start
                try await Task.sleep(for: .seconds(1))

                if !launchProcess.isRunning {
                    let launchErr =
                        String(
                            data: launchPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
                    FileHandle.standardError.write(
                        Data(
                            "[preview_capture] Binary launch failed (\(launchProcess.terminationStatus)): \(launchErr.suffix(500))\n"
                                .utf8))
                }

                try await Task.sleep(for: .seconds(renderDelay))

                // Verify the app is running
                let pgrepProcess = Process()
                pgrepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                pgrepProcess.arguments = ["-f", bundleId]
                let pgrepPipe = Pipe()
                pgrepProcess.standardOutput = pgrepPipe
                try? pgrepProcess.run()
                pgrepProcess.waitUntilExit()
                let pgrepOut =
                    String(
                        data: pgrepPipe.fileHandleForReading.readDataToEndOfFile(),
                        encoding: .utf8) ?? ""
                FileHandle.standardError.write(
                    Data(
                        "[preview_capture] pgrep for \(bundleId): \(pgrepOut.isEmpty ? "NOT RUNNING" : pgrepOut.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                            .utf8))

                screenshotData = try await captureMacOSWindow(bundleId: bundleId)

                // Terminate the app
                let killProcess = Process()
                killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killProcess.arguments = ["-f", bundleId]
                try? killProcess.run()
                killProcess.waitUntilExit()
            } else {
                // iOS Simulator: use simctl
                let sim = simulator!

                let installResult = try await simctlRunner.install(
                    udid: sim, appPath: appPath)
                if !installResult.succeeded {
                    throw MCPError.internalError(
                        "Failed to install preview app: \(installResult.stderr.isEmpty ? installResult.stdout : installResult.stderr)"
                    )
                }

                let launchResult = try await simctlRunner.launch(
                    udid: sim, bundleId: bundleId)
                if !launchResult.succeeded {
                    throw MCPError.internalError(
                        "Failed to launch preview app: \(launchResult.stderr.isEmpty ? launchResult.stdout : launchResult.stderr)"
                    )
                }

                // Wait briefly for launch, then bring to foreground by opening
                // via simctl (launch alone may leave app behind springboard)
                try await Task.sleep(for: .seconds(1.0))
                _ = try? await simctlRunner.launch(
                    udid: sim, bundleId: bundleId)

                try await Task.sleep(for: .seconds(renderDelay))

                let screenshotPath = "\(tempDirectory)/preview.png"
                let screenshotResult = try await simctlRunner.screenshot(
                    udid: sim, outputPath: screenshotPath)
                if !screenshotResult.succeeded {
                    throw MCPError.internalError(
                        "Failed to capture screenshot: \(screenshotResult.stderr.isEmpty ? screenshotResult.stdout : screenshotResult.stderr)"
                    )
                }

                screenshotData = try Data(contentsOf: URL(fileURLWithPath: screenshotPath))

                _ = try? await simctlRunner.terminate(udid: sim, bundleId: bundleId)
            }

            let base64 = screenshotData.base64EncodedString()

            // Save to user-specified path if requested
            if let savePath {
                // Allow absolute paths without base-path restriction
                let resolvedSavePath =
                    savePath.hasPrefix("/")
                    ? savePath : try pathUtility.resolvePath(from: savePath)
                try screenshotData.write(to: URL(fileURLWithPath: resolvedSavePath))
            }

            // Build result
            var description = "Preview screenshot captured"
            if let name = preview.name {
                description += " for \"\(name)\""
            }
            description += " from \(filePath)"
            if let savePath {
                description += "\nSaved to: \(savePath)"
            }

            let result = CallTool.Result(content: [
                .image(data: base64, mimeType: "image/png", metadata: nil),
                .text(description),
            ])

            // Cleanup
            cleanup(
                projectPath: resolvedProjectPath, targetName: injectedTargetName,
                tempDir: tempDir, schemePath: schemePath, xcconfigPath: xcconfigPath)
            return result
        } catch {
            cleanup(
                projectPath: resolvedProjectPath, targetName: injectedTargetName,
                tempDir: tempDir, schemePath: schemePath, xcconfigPath: xcconfigPath)
            throw error.asMCPError()
        }
    }

    // MARK: - Private Helpers

    /// Finds the native target that owns the given source file.
    private func findOwningTarget(
        for filePath: String, in xcodeproj: XcodeProj, projectDir: String
    ) -> (PBXNativeTarget?, Bool) {
        // First try: check explicit source build phase files
        for target in xcodeproj.pbxproj.nativeTargets {
            for buildPhase in target.buildPhases {
                guard let sourcesPhase = buildPhase as? PBXSourcesBuildPhase else { continue }
                for file in sourcesPhase.files ?? [] {
                    guard let fileRef = file.file else { continue }
                    if let fullPath = try? fileRef.fullPath(sourceRoot: Path(projectDir)),
                        fullPath.string == filePath || filePath.hasSuffix(fullPath.string)
                    {
                        let isApp = target.productType == .application
                        return (target, isApp)
                    }
                }
            }
        }

        // Second try: check fileSystemSynchronizedGroups (Xcode 16+ folder-based sources)
        for target in xcodeproj.pbxproj.nativeTargets {
            guard let syncGroups = target.fileSystemSynchronizedGroups else { continue }
            for group in syncGroups {
                if let groupPath = try? group.fullPath(sourceRoot: Path(projectDir)) {
                    let groupDir = groupPath.string
                    if filePath.hasPrefix(groupDir + "/") || filePath == groupDir {
                        let isApp = target.productType == .application
                        return (target, isApp)
                    }
                }
            }
        }

        return (nil, false)
    }

    /// Collects all Swift source files from an app target's synchronized groups,
    /// excluding files that contain `@main` (to avoid conflicts with the preview host).
    private func collectAppSourceFiles(
        target: PBXNativeTarget,
        xcodeproj: XcodeProj,
        projectDir: String
    ) -> [String] {
        var sourceFiles: [String] = []
        let fm = FileManager.default

        // Collect from fileSystemSynchronizedGroups
        if let syncGroups = target.fileSystemSynchronizedGroups {
            for group in syncGroups {
                guard let groupPath = try? group.fullPath(sourceRoot: Path(projectDir)) else {
                    continue
                }
                let dirPath = groupPath.string
                guard let enumerator = fm.enumerator(atPath: dirPath) else { continue }
                while let relativePath = enumerator.nextObject() as? String {
                    guard relativePath.hasSuffix(".swift") else { continue }
                    let fullPath = "\(dirPath)/\(relativePath)"
                    // Skip files with @main to avoid duplicate entry points
                    if let contents = try? String(contentsOfFile: fullPath, encoding: .utf8),
                        contents.contains("@main")
                    {
                        continue
                    }
                    sourceFiles.append(fullPath)
                }
            }
        }

        // Also collect from explicit source build phase files
        for buildPhase in target.buildPhases {
            guard let sourcesPhase = buildPhase as? PBXSourcesBuildPhase else { continue }
            for file in sourcesPhase.files ?? [] {
                guard let fileRef = file.file,
                    let fullPath = try? fileRef.fullPath(sourceRoot: Path(projectDir))
                else { continue }
                let path = fullPath.string
                guard path.hasSuffix(".swift") else { continue }
                if let contents = try? String(contentsOfFile: path, encoding: .utf8),
                    contents.contains("@main")
                {
                    continue
                }
                if !sourceFiles.contains(path) {
                    sourceFiles.append(path)
                }
            }
        }

        return sourceFiles
    }

    /// Recursively collects transitive framework dependencies of a target.
    private func collectTransitiveDependencies(
        of target: PBXNativeTarget, in xcodeproj: XcodeProj,
        collected: inout [PBXNativeTarget]
    ) {
        for dep in target.dependencies {
            if dep.target == nil {
                FileHandle.standardError.write(
                    Data(
                        "[preview_capture]   dep of \(target.name): target=nil, proxy=\(dep.targetProxy?.remoteInfo ?? "nil")\n"
                            .utf8))
            }
            guard let depTarget = dep.target as? PBXNativeTarget else { continue }
            guard !collected.contains(where: { $0 === depTarget }) else { continue }
            if depTarget.productType == .framework
                || depTarget.productType == .staticFramework
            {
                collected.append(depTarget)
                collectTransitiveDependencies(
                    of: depTarget, in: xcodeproj, collected: &collected)
            } else {
                FileHandle.standardError.write(
                    Data(
                        "[preview_capture]   skipping \(depTarget.name) (productType=\(depTarget.productType?.rawValue ?? "nil"))\n"
                            .utf8))
            }
        }
    }

    /// Extracts the iOS deployment target from a target's build configurations.
    private func extractDeploymentTarget(from target: PBXNativeTarget?) -> String? {
        guard let configList = target?.buildConfigurationList else { return nil }
        for config in configList.buildConfigurations {
            if let value = config.buildSettings["IPHONEOS_DEPLOYMENT_TARGET"] {
                switch value {
                case let .string(s): return s
                default: continue
                }
            }
        }
        return nil
    }

    /// Generates the SwiftUI host app source code.
    /// For framework targets, imports the module so public types are available.
    /// For app targets, the source file is compiled directly (no import needed).
    ///
    /// The preview body is placed in a top-level function rather than inline
    /// in the WindowGroup closure. Preview bodies may contain nested struct
    /// definitions (e.g. `struct MyShape: Shape { ... }`); when these are
    /// nested inside struct → computed property → closure, the Swift compiler's
    /// ASTMangler enters infinite recursion mangling the nested type context.
    /// A top-level function avoids this depth.
    private func generateHostSource(
        previewBody: String,
        moduleName: String? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("import SwiftUI")
        if let moduleName {
            lines.append("import \(moduleName)")
        }

        // Place preview body in a top-level function to avoid ASTMangler crash.
        lines.append("")
        lines.append("func _previewContent() -> some View {")
        let bodyLines = previewBody.split(separator: "\n", omittingEmptySubsequences: false)
        for line in bodyLines {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.isEmpty {
                lines.append("")
            } else {
                lines.append("    \(trimmed)")
            }
        }
        lines.append("}")

        lines.append("")
        lines.append("@main")
        lines.append("struct PreviewHostApp: App {")
        lines.append("    var body: some Scene {")
        lines.append("        WindowGroup {")
        lines.append("            _previewContent()")
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Injects a temporary target into the Xcode project.
    private func injectTarget(
        xcodeproj: XcodeProj,
        projectPath: String,
        targetName: String,
        bundleId: String,
        hostSourcePath: String,
        additionalSourcePaths: [String],
        sourceTarget: PBXNativeTarget?,
        isAppTarget: Bool,
        deploymentTarget: String?
    ) throws {
        let projectURL = URL(fileURLWithPath: projectPath)

        // Build settings — copy platform settings from source target if available
        var debugSettings: [String: BuildSetting] = [
            "PRODUCT_NAME": .string(targetName),
            "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleId),
            "GENERATE_INFOPLIST_FILE": .string("YES"),
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": .string("YES"),
            "INFOPLIST_KEY_UILaunchScreen_Generation": .string("YES"),
            "SDKROOT": .string("auto"),
            "SWIFT_VERSION": .string("5.0"),
            "TARGETED_DEVICE_FAMILY": .string("1,2"),
            "LD_RUNPATH_SEARCH_PATHS": .array([
                "$(inherited)",
                "@executable_path/Frameworks",
                "@executable_path/../Frameworks",
            ]),
            // Prevent merging framework dependencies into the app binary.
            // Projects using Xcode 15+ mergeable libraries produce empty
            // framework bundles (no dylib). Setting this to "none" forces
            // the build system to produce separate dynamic frameworks that
            // the preview host can link against.
            "MERGED_BINARY_TYPE": .string("none"),
        ]

        // Copy platform-related build settings from source target.
        // Note: these settings may be inherited from the project level rather
        // than set on the target config, so we also resolve them via xcodebuild
        // -showBuildSettings at the call site if needed.
        if let sourceConfig = sourceTarget?.buildConfigurationList?.buildConfigurations.first {
            for key in [
                "IPHONEOS_DEPLOYMENT_TARGET",
                "MACOSX_DEPLOYMENT_TARGET", "SUPPORTS_MACCATALYST",
            ] {
                if let value = sourceConfig.buildSettings[key] {
                    debugSettings[key] = value
                }
            }

            // Don't copy SDKROOT or SUPPORTED_PLATFORMS from the source target.
            // SDKROOT may be a resolved absolute path that causes issues.
            // SUPPORTED_PLATFORMS from the source may restrict to a single
            // platform (e.g., macOS-only), but the preview host must always
            // support iOS Simulator for destination matching to work.
        }

        // Always set SUPPORTED_PLATFORMS to include iOS Simulator so
        // xcodebuild destination matching works. This must be in the
        // project-level build settings (not just command-line overrides)
        // because xcodebuild resolves available destinations from the
        // project file before applying overrides.
        debugSettings["SUPPORTED_PLATFORMS"] = .string(
            "iphoneos iphonesimulator macosx")

        if let deploymentTarget, debugSettings["IPHONEOS_DEPLOYMENT_TARGET"] == nil {
            debugSettings["IPHONEOS_DEPLOYMENT_TARGET"] = .string(deploymentTarget)
        }

        let releaseSettings = debugSettings

        let debugConfig = XCBuildConfiguration(name: "Debug", buildSettings: debugSettings)
        let releaseConfig = XCBuildConfiguration(name: "Release", buildSettings: releaseSettings)
        xcodeproj.pbxproj.add(object: debugConfig)
        xcodeproj.pbxproj.add(object: releaseConfig)

        let configList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Debug"
        )
        xcodeproj.pbxproj.add(object: configList)

        // Sources build phase
        let sourcesBuildPhase = PBXSourcesBuildPhase()
        xcodeproj.pbxproj.add(object: sourcesBuildPhase)

        // Add host source file
        let hostFileRef = PBXFileReference(
            sourceTree: .absolute, name: "PreviewHostApp.swift", path: hostSourcePath
        )
        xcodeproj.pbxproj.add(object: hostFileRef)
        let hostBuildFile = PBXBuildFile(file: hostFileRef)
        xcodeproj.pbxproj.add(object: hostBuildFile)
        sourcesBuildPhase.files?.append(hostBuildFile)

        // Add additional source files (for app targets)
        for path in additionalSourcePaths {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            let fileRef = PBXFileReference(
                sourceTree: .absolute, name: fileName, path: path
            )
            xcodeproj.pbxproj.add(object: fileRef)
            let buildFile = PBXBuildFile(file: fileRef)
            xcodeproj.pbxproj.add(object: buildFile)
            sourcesBuildPhase.files?.append(buildFile)
        }

        // Frameworks build phase
        let frameworksBuildPhase = PBXFrameworksBuildPhase()
        xcodeproj.pbxproj.add(object: frameworksBuildPhase)

        // Resources build phase
        let resourcesBuildPhase = PBXResourcesBuildPhase()
        xcodeproj.pbxproj.add(object: resourcesBuildPhase)

        // Create the target
        let target = PBXNativeTarget(
            name: targetName,
            buildConfigurationList: configList,
            buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
            productType: .application
        )
        target.productName = targetName
        xcodeproj.pbxproj.add(object: target)

        if let sourceTarget {
            // For framework targets: link the framework itself + transitive deps
            //   (we import the module, so we need the framework binary).
            // For app targets: link the app's framework dependencies
            //   (source is compiled directly, so we don't link the app target itself).
            var frameworkDeps: [PBXNativeTarget] = []

            // For framework targets, include the source framework itself
            if !isAppTarget
                && (sourceTarget.productType == .framework
                    || sourceTarget.productType == .staticFramework)
            {
                frameworkDeps.append(sourceTarget)
            }

            collectTransitiveDependencies(
                of: sourceTarget, in: xcodeproj, collected: &frameworkDeps)

            FileHandle.standardError.write(
                Data(
                    "[preview_capture] sourceTarget: \(sourceTarget.name) (isApp=\(isAppTarget)), frameworkDeps: \(frameworkDeps.map { $0.name })\n"
                        .utf8))
            for fw in frameworkDeps {
                let pkgDeps = fw.packageProductDependencies ?? []
                if !pkgDeps.isEmpty {
                    FileHandle.standardError.write(
                        Data(
                            "[preview_capture]   \(fw.name) SPM deps: \(pkgDeps.map { $0.productName })\n"
                                .utf8))
                }
            }

            if !frameworkDeps.isEmpty {
                // Embed frameworks phase
                let embedPhase = PBXCopyFilesBuildPhase(
                    dstSubfolderSpec: .frameworks,
                    name: "Embed Frameworks"
                )
                xcodeproj.pbxproj.add(object: embedPhase)
                target.buildPhases.append(embedPhase)

                for fwTarget in frameworkDeps {
                    guard let product = fwTarget.product else { continue }
                    guard
                        fwTarget.productType == .framework
                            || fwTarget.productType == .staticFramework
                    else { continue }

                    // Add dependency
                    let dep = PBXTargetDependency(target: fwTarget)
                    xcodeproj.pbxproj.add(object: dep)
                    target.dependencies.append(dep)

                    // Link
                    let linkFile = PBXBuildFile(file: product)
                    xcodeproj.pbxproj.add(object: linkFile)
                    frameworksBuildPhase.files?.append(linkFile)

                    // Embed
                    let embedFile = PBXBuildFile(
                        file: product,
                        settings: ["ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]]
                    )
                    xcodeproj.pbxproj.add(object: embedFile)
                    embedPhase.files?.append(embedFile)
                }
            }

            // Collect and add SPM package product dependencies from the source
            // target and its transitive framework dependencies. Without this,
            // the preview host app crashes on launch because SPM-provided
            // frameworks (e.g., GRDB) aren't embedded.
            var collectedPackageDeps: [XCSwiftPackageProductDependency] = []
            let allTargets = [sourceTarget].compactMap { $0 } + frameworkDeps
            for srcTarget in allTargets {
                for dep in srcTarget.packageProductDependencies ?? [] {
                    if !collectedPackageDeps.contains(where: { $0.productName == dep.productName })
                    {
                        collectedPackageDeps.append(dep)
                    }
                }
            }

            if !collectedPackageDeps.isEmpty {
                var newPkgDeps: [XCSwiftPackageProductDependency] = []
                for pkgDep in collectedPackageDeps {
                    FileHandle.standardError.write(
                        Data(
                            "[preview_capture]   adding SPM dep: \(pkgDep.productName), package=\(pkgDep.package?.name ?? pkgDep.package?.repositoryURL ?? "nil")\n"
                                .utf8))
                    let newPkgDep = XCSwiftPackageProductDependency(
                        productName: pkgDep.productName,
                        package: pkgDep.package
                    )
                    xcodeproj.pbxproj.add(object: newPkgDep)
                    newPkgDeps.append(newPkgDep)

                    // Add as a build file to the frameworks build phase
                    let pkgBuildFile = PBXBuildFile(product: newPkgDep)
                    xcodeproj.pbxproj.add(object: pkgBuildFile)
                    frameworksBuildPhase.files?.append(pkgBuildFile)
                }
                target.packageProductDependencies = newPkgDeps
            }

            // Look for resource bundle targets
            let moduleResourceBundlePatterns = [
                "\(sourceTarget.name)_\(sourceTarget.name)",
                "\(sourceTarget.name)_Resources",
                "\(sourceTarget.name)Resources",
            ]

            for bundleTarget in xcodeproj.pbxproj.nativeTargets {
                if bundleTarget.productType == .bundle
                    && moduleResourceBundlePatterns.contains(bundleTarget.name)
                {
                    let bundleDep = PBXTargetDependency(target: bundleTarget)
                    xcodeproj.pbxproj.add(object: bundleDep)
                    target.dependencies.append(bundleDep)

                    if let bundleProduct = bundleTarget.product {
                        let resourceBuildFile = PBXBuildFile(file: bundleProduct)
                        xcodeproj.pbxproj.add(object: resourceBuildFile)
                        resourcesBuildPhase.files?.append(resourceBuildFile)
                    }
                }
            }
        }

        // Add target to project
        if let project = xcodeproj.pbxproj.rootObject {
            project.targets.append(target)
        }

        // Save project
        try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))
    }

    /// Runs xcodebuild tolerantly — if the process appears stuck but the build
    /// already succeeded (e.g., due to a slow post-build script), returns success.
    /// Copies any .framework bundles from the build products directory into
    /// the app's Frameworks/ folder if they aren't already there. This handles
    /// cross-project framework references (e.g., GRDB from a sub-xcodeproj)
    /// that get built as dependencies but aren't automatically embedded.
    private func embedMissingFrameworks(appPath: String) {
        let fm = FileManager.default
        let appURL = URL(fileURLWithPath: appPath)
        let frameworksDir = appURL.appendingPathComponent("Frameworks")
        let buildProductsDir = appURL.deletingLastPathComponent()

        // Ensure Frameworks/ exists
        try? fm.createDirectory(at: frameworksDir, withIntermediateDirectories: true)

        // Get already-embedded framework names
        let existing = (try? fm.contentsOfDirectory(atPath: frameworksDir.path)) ?? []
        let existingNames = Set(existing)

        // Find .framework bundles in the build products directory
        guard let items = try? fm.contentsOfDirectory(atPath: buildProductsDir.path) else { return }
        for item in items where item.hasSuffix(".framework") {
            guard !existingNames.contains(item) else { continue }
            let src = buildProductsDir.appendingPathComponent(item)
            let dst = frameworksDir.appendingPathComponent(item)
            try? fm.copyItem(at: src, to: dst)
        }
    }

    private func runBuildTolerant(
        arguments: [String], timeout: TimeInterval
    ) async throws -> XcodebuildResult {
        do {
            return try await xcodebuildRunner.run(
                arguments: arguments, timeout: timeout, onProgress: nil)
        } catch let error as XcodebuildError {
            let output = error.partialOutput
            if output.contains("Build succeeded") || output.contains("** BUILD SUCCEEDED **") {
                // Build succeeded but process hung (e.g., post-build indexing)
                return XcodebuildResult(exitCode: 0, stdout: output, stderr: "")
            }
            // Return as failed result instead of throwing, so callers can
            // inspect the output and try fallback strategies.
            return XcodebuildResult(exitCode: 1, stdout: output, stderr: "")
        }
    }

    /// Ensures the process has a WindowServer connection for ScreenCaptureKit.
    private static func ensureGUIConnection() async {
        await MainActor.run {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    /// Captures a screenshot of a macOS window using ScreenCaptureKit.
    /// Matches the window by bundle identifier.
    private func captureMacOSWindow(bundleId: String) async throws -> Data {
        await Self.ensureGUIConnection()

        let availableContent: SCShareableContent
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            throw MCPError.internalError(
                "Failed to get screen content. Ensure Screen Recording permission is granted in "
                    + "System Settings > Privacy & Security > Screen Recording. Error: \(error.localizedDescription)"
            )
        }

        // Find the window by bundle ID
        let matchingWindows = availableContent.windows.filter { window in
            guard let id = window.owningApplication?.bundleIdentifier else { return false }
            return id.localizedCaseInsensitiveContains(bundleId)
        }

        guard let targetWindow = matchingWindows.first else {
            throw MCPError.internalError(
                "No window found for preview app (bundle ID: \(bundleId)). "
                    + "The app may have failed to launch or display a window.")
        }

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))

        let cgImage: CGImage = try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: MCPError.internalError(
                            "Screenshot capture returned nil image."))
                }
            }
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw MCPError.internalError("Failed to encode screenshot as PNG.")
        }

        return pngData
    }

    /// Creates a temporary .xcscheme file for the preview host target.
    /// Returns the full path to the scheme file so it can be deleted after build.
    private func createTemporaryScheme(
        projectPath: String, targetName: String
    ) throws -> String {
        let projectURL = URL(fileURLWithPath: projectPath)
        let schemesDir =
            projectURL
            .appendingPathComponent("xcshareddata")
            .appendingPathComponent("xcschemes")

        try FileManager.default.createDirectory(
            at: schemesDir, withIntermediateDirectories: true)

        let schemePath =
            schemesDir
            .appendingPathComponent("\(targetName).xcscheme").path

        // Find the target's UUID in the pbxproj
        let xcodeproj = try XcodeProj(path: Path(projectPath))
        let targetRef = xcodeproj.pbxproj.nativeTargets
            .first { $0.name == targetName }

        let blueprintId = targetRef?.uuid ?? ""
        let projectName = projectURL.deletingPathExtension().lastPathComponent

        let buildRef = """
                        <BuildableReference
                           BuildableIdentifier = "primary"
                           BlueprintIdentifier = "\(blueprintId)"
                           BuildableName = "\(targetName).app"
                           BlueprintName = "\(targetName)"
                           ReferencedContainer = "container:\(projectName).xcodeproj">
                        </BuildableReference>
            """

        let schemeXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <Scheme
               LastUpgradeVersion = "2600"
               version = "2.1">
               <BuildAction
                  parallelizeBuildables = "YES"
                  buildImplicitDependencies = "YES">
                  <BuildActionEntries>
                     <BuildActionEntry
                        buildForTesting = "NO"
                        buildForRunning = "YES"
                        buildForProfiling = "NO"
                        buildForArchiving = "NO"
                        buildForAnalyzing = "NO">
            \(buildRef)
                     </BuildActionEntry>
                  </BuildActionEntries>
               </BuildAction>
               <LaunchAction
                  buildConfiguration = "Release"
                  selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
                  selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
                  launchStyle = "0"
                  useCustomWorkingDirectory = "NO"
                  ignoresPersistentStateOnLaunch = "NO"
                  debugDocumentVersioning = "YES"
                  debugServiceExtension = "internal"
                  allowLocationSimulation = "YES">
                  <BuildableProductRunnable
                     runnableDebuggingMode = "0">
            \(buildRef)
                  </BuildableProductRunnable>
               </LaunchAction>
            </Scheme>
            """

        try schemeXML.write(toFile: schemePath, atomically: true, encoding: .utf8)
        return schemePath
    }

    /// Finds the built .app path by querying xcodebuild for build settings.
    private func findBuiltAppPath(
        projectPath: String, targetName: String,
        destination: String, configuration: String
    ) async throws -> String {
        let args = [
            "-project", projectPath,
            "-scheme", targetName,
            "-destination", destination,
            "-configuration", configuration,
            "-showBuildSettings",
        ]
        let settingsResult = try await xcodebuildRunner.run(arguments: args)

        guard settingsResult.succeeded else {
            throw MCPError.internalError(
                "Failed to get build settings: \(settingsResult.stderr)")
        }

        // Parse BUILT_PRODUCTS_DIR from output
        var builtProductsDir: String?
        var productName: String?
        for line in settingsResult.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                builtProductsDir = String(trimmed.dropFirst("BUILT_PRODUCTS_DIR = ".count))
            }
            if trimmed.hasPrefix("FULL_PRODUCT_NAME = ") {
                productName = String(trimmed.dropFirst("FULL_PRODUCT_NAME = ".count))
            }
        }

        guard let dir = builtProductsDir, let name = productName else {
            throw MCPError.internalError(
                "Could not determine build products directory for target '\(targetName)'")
        }

        let appPath = "\(dir)/\(name)"
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw MCPError.internalError(
                "Built app not found at \(appPath)")
        }

        return appPath
    }

    /// Removes the injected target and cleans up temporary files.
    /// Never throws — logs errors silently.
    private func cleanup(
        projectPath: String?, targetName: String?, tempDir: String?,
        schemePath: String? = nil, xcconfigPath: String? = nil
    ) {
        // Remove injected target from project
        if let projectPath, let targetName {
            do {
                let xcodeproj = try XcodeProj(path: Path(projectPath))

                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    return
                }

                // Remove dependencies from other targets
                for otherTarget in xcodeproj.pbxproj.nativeTargets {
                    otherTarget.dependencies.removeAll { $0.target == target }
                }

                // Remove build phases and their files
                for buildPhase in target.buildPhases {
                    if let sourcesPhase = buildPhase as? PBXSourcesBuildPhase {
                        for file in sourcesPhase.files ?? [] {
                            if let fileRef = file.file {
                                xcodeproj.pbxproj.delete(object: fileRef)
                            }
                            xcodeproj.pbxproj.delete(object: file)
                        }
                    }
                    if let frameworksPhase = buildPhase as? PBXFrameworksBuildPhase {
                        for file in frameworksPhase.files ?? [] {
                            xcodeproj.pbxproj.delete(object: file)
                        }
                    }
                    if let resourcesPhase = buildPhase as? PBXResourcesBuildPhase {
                        for file in resourcesPhase.files ?? [] {
                            xcodeproj.pbxproj.delete(object: file)
                        }
                    }
                    if let copyPhase = buildPhase as? PBXCopyFilesBuildPhase {
                        for file in copyPhase.files ?? [] {
                            xcodeproj.pbxproj.delete(object: file)
                        }
                    }
                    xcodeproj.pbxproj.delete(object: buildPhase)
                }

                // Remove config list
                if let configList = target.buildConfigurationList {
                    for config in configList.buildConfigurations {
                        xcodeproj.pbxproj.delete(object: config)
                    }
                    xcodeproj.pbxproj.delete(object: configList)
                }

                // Remove product reference
                if let productRef = target.product {
                    if let project = xcodeproj.pbxproj.rootObject,
                        let productsGroup = project.productsGroup
                    {
                        productsGroup.children.removeAll { $0 == productRef }
                    }
                    xcodeproj.pbxproj.delete(object: productRef)
                }

                // Remove from project targets
                if let project = xcodeproj.pbxproj.rootObject {
                    project.targets.removeAll { $0 == target }
                }

                // Remove target group if exists
                if let project = try? xcodeproj.pbxproj.rootProject(),
                    let mainGroup = project.mainGroup
                {
                    mainGroup.children.removeAll { element in
                        if let group = element as? PBXGroup, group.name == targetName {
                            xcodeproj.pbxproj.delete(object: group)
                            return true
                        }
                        return false
                    }
                }

                // Delete target
                xcodeproj.pbxproj.delete(object: target)

                // Save
                try PBXProjWriter.write(xcodeproj, to: Path(projectPath))
            } catch {
                // Cleanup should never throw
            }
        }

        // Remove scheme file and xcconfig
        if let schemePath {
            try? FileManager.default.removeItem(atPath: schemePath)
        }
        if let xcconfigPath {
            try? FileManager.default.removeItem(atPath: xcconfigPath)
        }

        // Remove temp directory
        if let tempDir {
            try? FileManager.default.removeItem(atPath: tempDir)
        }
    }
}
