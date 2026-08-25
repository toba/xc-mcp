import MCP
import XCMCPCore

extension ToolRegistry {
    /// Swift tools.
    static let swift: [ToolRegistration] = [
    ToolRegistration("detect_unused_code", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = DetectUnusedCodeTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_diagnostics", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftDiagnosticsTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_format", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftFormatTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_lint", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftLintTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_package_build", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageBuildTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("swift_package_clean", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageCleanTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_package_docs", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageDocsTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ToolRegistration("swift_package_list", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageListTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_package_run", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageRunTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_package_stop", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageStopTool(sessionManager: deps.session)
        return (tool.tool(), { try await tool.execute(arguments: $0.arguments) })
    },
    ToolRegistration("swift_package_test", .swiftPackage, [.monolith, .swift]) { deps in
        let tool = SwiftPackageTestTool(swiftRunner: deps.swift, sessionManager: deps.session)
        return (tool.tool(), { call in
            try await call.withProgress { onProgress in
                try await tool.execute(arguments: call.arguments, onProgress: onProgress)
            }
        })
    },
    ]
}
