import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddTargetTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "add_target",
            description: "Create a new target",
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
                        "description": .string("Name of the target to create"),
                    ]),
                    "product_type": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Product type (application, framework, staticFramework, xcFramework, dynamicLibrary, staticLibrary, bundle, unitTestBundle, uiTestBundle, appExtension, extensionKitExtension, commandLineTool, watchApp, watch2App, watch2AppContainer, watchExtension, watch2Extension, tvExtension, messagesApplication, messagesExtension, stickerPack, xpcService, ocUnitTestBundle, xcodeExtension, instrumentsPackage, intentsServiceExtension, onDemandInstallCapableApplication, metalLibrary, driverExtension, systemExtension)",
                        ),
                    ]),
                    "bundle_identifier": .object([
                        "type": .string("string"),
                        "description": .string("Bundle identifier for the target"),
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Platform (iOS, macOS, tvOS, watchOS) - optional, defaults to iOS)",
                        ),
                    ]),
                    "deployment_target": .object([
                        "type": .string("string"),
                        "description": .string("Deployment target version (optional)"),
                    ]),
                    "parent_group": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Group to nest the target's folder under (e.g. 'Components' or 'Modules/UI'). Optional, defaults to project root.",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"), .string("product_type"),
                    .string("bundle_identifier"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(productTypeString) = arguments["product_type"],
              case let .string(bundleIdentifier) = arguments["bundle_identifier"] else {
            throw MCPError.invalidParams(
                "project_path, target_name, product_type, and bundle_identifier are required",
            )
        }

        let platform: String

        if case let .string(plat) = arguments["platform"] {
            platform = plat
        } else {
            platform = "iOS"
        }

        let deploymentTarget: String?

        if case let .string(target) = arguments["deployment_target"] {
            deploymentTarget = target
        } else {
            deploymentTarget = nil
        }

        let parentGroupPath: String?

        if case let .string(pg) = arguments["parent_group"] {
            parentGroupPath = pg
        } else {
            parentGroupPath = nil
        }

        // Map product type string to PBXProductType
        let productType: PBXProductType

        switch productTypeString.lowercased() {
            case "application", "app": productType = .application
            case "framework": productType = .framework
            case "staticframework", "static_framework": productType = .staticFramework
            case "xcframework", "xc_framework": productType = .xcFramework
            case "dynamiclibrary", "dynamic_library": productType = .dynamicLibrary
            case "staticlibrary", "static_library": productType = .staticLibrary
            case "bundle": productType = .bundle
            case "unittestbundle", "unit_test_bundle": productType = .unitTestBundle
            case "uitestbundle", "ui_test_bundle": productType = .uiTestBundle
            case "appextension", "app_extension": productType = .appExtension
            case "extensionkitextension", "extensionkit_extension":
                productType = .extensionKitExtension
            case "commandlinetool", "command_line_tool": productType = .commandLineTool
            case "watchapp", "watch_app": productType = .watchApp
            case "watch2app", "watch2_app", "watch_2_app": productType = .watch2App
            case "watch2appcontainer", "watch2_app_container", "watch_2_app_container":
                productType = .watch2AppContainer
            case "watchextension", "watch_extension": productType = .watchExtension
            case "watch2extension", "watch2_extension", "watch_2_extension":
                productType = .watch2Extension
            case "tvextension", "tv_extension": productType = .tvExtension
            case "messagesapplication", "messages_application": productType = .messagesApplication
            case "messagesextension", "messages_extension": productType = .messagesExtension
            case "stickerpack", "sticker_pack": productType = .stickerPack
            case "xpcservice", "xpc_service": productType = .xpcService
            case "ocunittestbundle", "oc_unit_test_bundle": productType = .ocUnitTestBundle
            case "xcodeextension", "xcode_extension": productType = .xcodeExtension
            case "instrumentspackage", "instruments_package": productType = .instrumentsPackage
            case "intentsserviceextension", "intents_service_extension":
                productType = .intentsServiceExtension
            case "ondemandinstallcapableapplication", "on_demand_install_capable_application":
                productType = .onDemandInstallCapableApplication
            case "metallibrary", "metal_library": productType = .metalLibrary
            case "driverextension", "driver_extension": productType = .driverExtension
            case "systemextension", "system_extension": productType = .systemExtension
            default: throw MCPError.invalidParams("Invalid product type: \(productTypeString)")
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Check if target already exists
            if xcodeproj.pbxproj.nativeTargets.contains(where: { $0.name == targetName }) {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "Target '\(targetName)' already exists in project",
                            annotations: nil,
                            _meta: nil,
                        )
                    ],
                )
            }

            // Introspect project-level build configurations to match all config names
            let projectConfigs: [XCBuildConfiguration]

            if let projectConfigList = xcodeproj.pbxproj.rootObject?.buildConfigurationList {
                projectConfigs = projectConfigList.buildConfigurations
            } else {
                projectConfigs = []
            }

            // If project has configs, use those names; otherwise fall back to Debug/Release
            let configNames: [String]
            configNames = projectConfigs.isEmpty
                ? ["Debug", "Release"]
                : projectConfigs.map(\.name)

            // Minimal target-specific settings
            let baseSettings: [String: BuildSetting] = [
                "PRODUCT_NAME": .string(targetName),
                "PRODUCT_BUNDLE_IDENTIFIER": .string(bundleIdentifier),
                "GENERATE_INFOPLIST_FILE": .string("YES"),
            ]

            // Add deployment target if specified
            let deploymentKey: String? =
                if deploymentTarget != nil {
                    platform == "iOS"
                        ? "IPHONEOS_DEPLOYMENT_TARGET"
                        : platform == "macOS"
                            ? "MACOSX_DEPLOYMENT_TARGET"
                            : platform == "tvOS"
                                ? "TVOS_DEPLOYMENT_TARGET"
                                : "WATCHOS_DEPLOYMENT_TARGET"
                } else {
                    nil
                }

            var targetBuildConfigs: [XCBuildConfiguration] = []

            for configName in configNames {
                var settings = baseSettings
                if let deploymentKey, let deploymentTarget {
                    settings[deploymentKey] = .string(deploymentTarget)
                }
                let config = XCBuildConfiguration(name: configName, buildSettings: settings)
                xcodeproj.pbxproj.add(object: config)
                targetBuildConfigs.append(config)
            }

            // Create target configuration list
            let targetConfigurationList = XCConfigurationList(
                buildConfigurations: targetBuildConfigs,
                defaultConfigurationName: "Release",
            )
            xcodeproj.pbxproj.add(object: targetConfigurationList)

            // Create build phases
            let sourcesBuildPhase = PBXSourcesBuildPhase()
            xcodeproj.pbxproj.add(object: sourcesBuildPhase)

            let resourcesBuildPhase = PBXResourcesBuildPhase()
            xcodeproj.pbxproj.add(object: resourcesBuildPhase)

            let frameworksBuildPhase = PBXFrameworksBuildPhase()
            xcodeproj.pbxproj.add(object: frameworksBuildPhase)

            // Create product reference
            let productName: String

            if let ext = productType.fileExtension {
                productName = "\(targetName).\(ext)"
            } else {
                productName = targetName
            }

            let productReference = PBXFileReference(
                sourceTree: .buildProductsDir,
                explicitFileType: productType.explicitFileType,
                path: productName,
                includeInIndex: false,
            )
            xcodeproj.pbxproj.add(object: productReference)

            // Create target
            let target = PBXNativeTarget(
                name: targetName,
                buildConfigurationList: targetConfigurationList,
                buildPhases: [sourcesBuildPhase, frameworksBuildPhase, resourcesBuildPhase],
                productType: productType,
            )
            target.productName = targetName
            target.product = productReference
            xcodeproj.pbxproj.add(object: target)

            // Add target to project and product to Products group
            if let project = xcodeproj.pbxproj.rootObject {
                project.targets.append(target)
                project.productsGroup?.children.append(productReference)
            }

            // Create target folder in the appropriate group
            if let project = try xcodeproj.pbxproj.rootProject(),
               let mainGroup = project.mainGroup
            {
                let targetGroup = PBXGroup(sourceTree: .group, name: targetName)
                xcodeproj.pbxproj.add(object: targetGroup)

                let containerGroup: PBXGroup

                if let parentGroupPath {
                    containerGroup = try mainGroup.resolveGroupPath(parentGroupPath)
                } else {
                    containerGroup = mainGroup
                }
                containerGroup.children.append(targetGroup)
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        text:
                            "Successfully created target '\(targetName)' with product type '\(productTypeString)' and bundle identifier '\(bundleIdentifier)'",
                        annotations: nil, _meta: nil)
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to create target in Xcode project: \(error.localizedDescription)",
            )
        }
    }
}

extension PBXProductType {
    var explicitFileType: String? {
        switch self {
            case .application,
                 .watchApp,
                 .watch2App,
                 .watch2AppContainer,
                 .onDemandInstallCapableApplication: "wrapper.application"
            case .messagesApplication: "wrapper.application"
            case .framework: "wrapper.framework"
            case .staticFramework: "wrapper.framework.static"
            case .xcFramework: "wrapper.xcframework"
            case .staticLibrary: "archive.ar"
            case .dynamicLibrary: "compiled.mach-o.dylib"
            case .bundle: "wrapper.cfbundle"
            case .unitTestBundle, .uiTestBundle, .ocUnitTestBundle: "wrapper.cfbundle"
            case .appExtension,
                 .extensionKitExtension,
                 .watchExtension,
                 .watch2Extension,
                 .tvExtension,
                 .messagesExtension,
                 .stickerPack,
                 .xcodeExtension,
                 .intentsServiceExtension,
                 .driverExtension,
                 .systemExtension:
                "wrapper.app-extension"
            case .commandLineTool: "compiled.mach-o.executable"
            case .xpcService: "wrapper.xpc-service"
            case .instrumentsPackage: "com.apple.instruments.instrdst"
            case .metalLibrary: "file.metallib"
            case .none: nil
        }
    }

    var fileExtension: String? {
        switch self {
            case .application,
                 .watchApp,
                 .watch2App,
                 .watch2AppContainer,
                 .messagesApplication,
                 .onDemandInstallCapableApplication: "app"
            case .framework, .staticFramework: "framework"
            case .xcFramework: "xcframework"
            case .staticLibrary: "a"
            case .dynamicLibrary: "dylib"
            case .bundle: "bundle"
            case .unitTestBundle, .uiTestBundle, .ocUnitTestBundle: "xctest"
            case .appExtension,
                 .extensionKitExtension,
                 .watchExtension,
                 .watch2Extension,
                 .tvExtension,
                 .messagesExtension,
                 .stickerPack,
                 .xcodeExtension,
                 .intentsServiceExtension,
                 .driverExtension,
                 .systemExtension: "appex"
            case .commandLineTool: nil
            case .xpcService: "xpc"
            case .instrumentsPackage: "instrdst"
            case .metalLibrary: "metallib"
            case .none: nil
        }
    }
}
