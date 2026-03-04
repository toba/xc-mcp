// Adapted from xcsift (MIT License) - https://github.com/ldomaradzki/xcsift
import Foundation

/// Result of parsing xcodebuild or swift build output.
public struct BuildResult: Sendable {
    public let status: String
    public let summary: BuildSummary
    public let errors: [BuildError]
    public let warnings: [BuildWarning]
    public let failedTests: [FailedTest]
    public let linkerErrors: [LinkerError]
    public let coverage: CodeCoverage?
    public let slowTests: [SlowTest]
    public let flakyTests: [String]
    public let buildInfo: BuildInfo?
    public let executables: [Executable]
    public let performanceMeasurements: [PerformanceMeasurement]

    public init(
        status: String,
        summary: BuildSummary,
        errors: [BuildError],
        warnings: [BuildWarning],
        failedTests: [FailedTest],
        linkerErrors: [LinkerError] = [],
        coverage: CodeCoverage? = nil,
        slowTests: [SlowTest] = [],
        flakyTests: [String] = [],
        buildInfo: BuildInfo? = nil,
        executables: [Executable] = [],
        performanceMeasurements: [PerformanceMeasurement] = [],
    ) {
        self.status = status
        self.summary = summary
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.linkerErrors = linkerErrors
        self.coverage = coverage
        self.slowTests = slowTests
        self.flakyTests = flakyTests
        self.buildInfo = buildInfo
        self.executables = executables
        self.performanceMeasurements = performanceMeasurements
    }
}

public struct BuildSummary: Sendable {
    public let errors: Int
    public let warnings: Int
    public let failedTests: Int
    public let linkerErrors: Int
    public let passedTests: Int?
    public let buildTime: String?
    public let testTime: String?
    public let coveragePercent: Double?
    public let slowTests: Int?
    public let flakyTests: Int?
    public let executables: Int?

    public init(
        errors: Int,
        warnings: Int,
        failedTests: Int,
        linkerErrors: Int = 0,
        passedTests: Int?,
        buildTime: String?,
        testTime: String? = nil,
        coveragePercent: Double? = nil,
        slowTests: Int? = nil,
        flakyTests: Int? = nil,
        executables: Int? = nil,
    ) {
        self.errors = errors
        self.warnings = warnings
        self.failedTests = failedTests
        self.linkerErrors = linkerErrors
        self.passedTests = passedTests
        self.buildTime = buildTime
        self.testTime = testTime
        self.coveragePercent = coveragePercent
        self.slowTests = slowTests
        self.flakyTests = flakyTests
        self.executables = executables
    }
}

public struct BuildError: Sendable {
    public let file: String?
    public let line: Int?
    public let message: String
    public let column: Int?

    public init(file: String?, line: Int?, message: String, column: Int? = nil) {
        self.file = file
        self.line = line
        self.message = message
        self.column = column
    }
}

public enum WarningType: String, Sendable {
    case compile
    case runtime
    case swiftui
}

public struct BuildWarning: Sendable {
    public let file: String?
    public let line: Int?
    public let message: String
    public let type: WarningType
    public let column: Int?

    public init(
        file: String?,
        line: Int?,
        message: String,
        type: WarningType = .compile,
        column: Int? = nil,
    ) {
        self.file = file
        self.line = line
        self.message = message
        self.type = type
        self.column = column
    }
}

public struct FailedTest: Sendable {
    public let test: String
    public let message: String
    public let file: String?
    public let line: Int?
    public let duration: Double?

    public init(test: String, message: String, file: String?, line: Int?, duration: Double? = nil) {
        self.test = test
        self.message = message
        self.file = file
        self.line = line
        self.duration = duration
    }
}

public struct CodeCoverage: Sendable {
    public let lineCoverage: Double
    public let files: [FileCoverage]

    public init(lineCoverage: Double, files: [FileCoverage]) {
        self.lineCoverage = lineCoverage
        self.files = files
    }
}

public struct FileCoverage: Sendable {
    public let path: String
    public let name: String
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int

    public init(
        path: String, name: String, lineCoverage: Double, coveredLines: Int, executableLines: Int,
    ) {
        self.path = path
        self.name = name
        self.lineCoverage = lineCoverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
    }
}

public struct LinkerError: Sendable {
    public let symbol: String
    public let architecture: String
    public let referencedFrom: String
    public let message: String
    public let conflictingFiles: [String]

    public init(
        symbol: String,
        architecture: String,
        referencedFrom: String,
        message: String = "",
    ) {
        self.symbol = symbol
        self.architecture = architecture
        self.referencedFrom = referencedFrom
        self.message = message
        conflictingFiles = []
    }

    public init(message: String) {
        symbol = ""
        architecture = ""
        referencedFrom = ""
        self.message = message
        conflictingFiles = []
    }

    public init(symbol: String, architecture: String, conflictingFiles: [String]) {
        self.symbol = symbol
        self.architecture = architecture
        referencedFrom = ""
        message = ""
        self.conflictingFiles = conflictingFiles
    }
}

public struct SlowTest: Sendable {
    public let test: String
    public let duration: Double

    public init(test: String, duration: Double) {
        self.test = test
        self.duration = duration
    }
}

public struct PerformanceMeasurement: Sendable {
    public let test: String
    public let metric: String
    public let average: Double
    public let relativeStandardDeviation: Double
    public let values: [Double]

    public init(
        test: String,
        metric: String,
        average: Double,
        relativeStandardDeviation: Double,
        values: [Double],
    ) {
        self.test = test
        self.metric = metric
        self.average = average
        self.relativeStandardDeviation = relativeStandardDeviation
        self.values = values
    }
}

public struct BuildInfo: Sendable {
    public let targets: [TargetBuildInfo]
    public let slowestTargets: [String]

    public init(targets: [TargetBuildInfo] = [], slowestTargets: [String] = []) {
        self.targets = targets
        self.slowestTargets = slowestTargets
    }
}

public struct TargetBuildInfo: Sendable {
    public let name: String
    public let duration: String?
    public let phases: [String]
    public let dependsOn: [String]

    public init(
        name: String, duration: String? = nil, phases: [String] = [], dependsOn: [String] = [],
    ) {
        self.name = name
        self.duration = duration
        self.phases = phases
        self.dependsOn = dependsOn
    }
}

public struct Executable: Sendable {
    public let path: String
    public let name: String
    public let target: String

    public init(path: String, name: String, target: String) {
        self.path = path
        self.name = name
        self.target = target
    }
}

// MARK: - Coverage Report Models

/// Per-target coverage data from an xcresult bundle.
public struct TargetCoverage: Sendable {
    public let name: String
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let files: [FileCoverage]

    public init(
        name: String,
        lineCoverage: Double,
        coveredLines: Int,
        executableLines: Int,
        files: [FileCoverage],
    ) {
        self.name = name
        self.lineCoverage = lineCoverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.files = files
    }
}

/// Top-level coverage report with per-target breakdown.
public struct CoverageReport: Sendable {
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let targets: [TargetCoverage]

    public init(
        lineCoverage: Double,
        coveredLines: Int,
        executableLines: Int,
        targets: [TargetCoverage],
    ) {
        self.lineCoverage = lineCoverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.targets = targets
    }
}

/// Function-level coverage data.
public struct FunctionCoverage: Sendable {
    public let name: String
    public let lineNumber: Int
    public let coveredLines: Int
    public let executableLines: Int
    public let lineCoverage: Double
    public let executionCount: Int

    public init(
        name: String,
        lineNumber: Int,
        coveredLines: Int,
        executableLines: Int,
        lineCoverage: Double,
        executionCount: Int,
    ) {
        self.name = name
        self.lineNumber = lineNumber
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.lineCoverage = lineCoverage
        self.executionCount = executionCount
    }
}

/// File-level coverage with function breakdown.
public struct FileFunctionCoverage: Sendable {
    public let path: String
    public let lineCoverage: Double
    public let coveredLines: Int
    public let executableLines: Int
    public let functions: [FunctionCoverage]

    public init(
        path: String,
        lineCoverage: Double,
        coveredLines: Int,
        executableLines: Int,
        functions: [FunctionCoverage],
    ) {
        self.path = path
        self.lineCoverage = lineCoverage
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.functions = functions
    }
}

/// A range of uncovered lines.
public struct UncoveredRange: Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}
