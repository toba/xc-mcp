import Testing
@testable import XCMCPCore
@testable import XCMCPTools
import Foundation

struct PerformanceMetricsTests {
    // MARK: - Format Metrics

    @Test
    func `Format metrics with multiple tests and metrics`() {
        let results = [
            XCResultParser.PerformanceMetricResult(
                testIdentifier: "DOMTests/testSorting()",
                testIdentifierURL: nil,
                testRuns: [
                    XCResultParser.TestRunWithMetrics(
                        testPlanConfiguration: XCResultParser.MetricConfiguration(
                            configurationId: "config-1",
                            configurationName: "Test Scheme Action",
                        ),
                        device: XCResultParser.MetricDevice(
                            deviceId: "device-1",
                            deviceName: "My Mac",
                        ),
                        metrics: [
                            XCResultParser.PerformanceMetric(
                                displayName: "Wall Clock Time",
                                unitOfMeasurement: "s",
                                measurements: [0.040, 0.042, 0.044, 0.041, 0.043],
                                identifier: "com.apple.dt.XCTMetric_Clock.time.monotonic",
                                baselineName: nil,
                                baselineAverage: 0.040,
                                maxRegression: nil,
                                maxPercentRegression: nil,
                                maxStandardDeviation: nil,
                                maxPercentRelativeStandardDeviation: nil,
                                polarity: nil,
                            ),
                            XCResultParser.PerformanceMetric(
                                displayName: "Memory Peak Physical",
                                unitOfMeasurement: "kB",
                                measurements: [15000, 15200, 15100, 15300, 15400],
                                identifier: "com.apple.dt.XCTMetric_Memory.physical_peak",
                                baselineName: nil,
                                baselineAverage: nil,
                                maxRegression: nil,
                                maxPercentRegression: nil,
                                maxStandardDeviation: nil,
                                maxPercentRelativeStandardDeviation: nil,
                                polarity: nil,
                            ),
                        ],
                    ),
                ],
            ),
        ]

        let output = GetPerformanceMetricsTool.formatMetrics(results)

        #expect(output.contains("Performance Metrics"))
        #expect(output.contains("DOMTests/testSorting()"))
        #expect(output.contains("Wall Clock Time"))
        #expect(output.contains("baseline"))
        #expect(output.contains("Memory Peak Physical"))
        #expect(output.contains("5 iterations"))
    }

    @Test
    func `Format metrics without baseline omits baseline`() {
        let results = [
            XCResultParser.PerformanceMetricResult(
                testIdentifier: "Tests/testFoo()",
                testIdentifierURL: nil,
                testRuns: [
                    XCResultParser.TestRunWithMetrics(
                        testPlanConfiguration: XCResultParser.MetricConfiguration(
                            configurationId: "c1", configurationName: "Config",
                        ),
                        device: XCResultParser.MetricDevice(
                            deviceId: "d1", deviceName: "Mac",
                        ),
                        metrics: [
                            XCResultParser.PerformanceMetric(
                                displayName: "Clock Time",
                                unitOfMeasurement: "s",
                                measurements: [1.0, 2.0, 3.0],
                                identifier: nil,
                                baselineName: nil,
                                baselineAverage: nil,
                                maxRegression: nil,
                                maxPercentRegression: nil,
                                maxStandardDeviation: nil,
                                maxPercentRelativeStandardDeviation: nil,
                                polarity: nil,
                            ),
                        ],
                    ),
                ],
            ),
        ]

        let output = GetPerformanceMetricsTool.formatMetrics(results)

        #expect(!output.contains("baseline"))
        #expect(output.contains("3 iterations"))
    }

    @Test
    func `Empty metrics array produces header only`() {
        let output = GetPerformanceMetricsTool.formatMetrics([])
        #expect(output.contains("Performance Metrics"))
        #expect(!output.contains("iterations"))
    }

    // MARK: - MachineMetadata

    @Test
    func `MachineMetadata returns valid info`() {
        let info = MachineMetadata.current()
        #expect(!info.cpuBrandString.isEmpty)
        #expect(info.coreCount > 0)
        #expect(!info.modelCode.isEmpty)
        #expect(info.ramMegabytes > 0)
    }

    // MARK: - Deterministic UUID

    @Test
    func `Deterministic UUID is stable`() {
        let info = MachineMetadata.Info(
            cpuBrandString: "Apple M1 Max",
            coreCount: 10,
            modelCode: "MacBookPro18,4",
            ramMegabytes: 65536,
        )
        let uuid1 = SetPerformanceBaselineTool.deterministicUUID(from: info)
        let uuid2 = SetPerformanceBaselineTool.deterministicUUID(from: info)
        #expect(uuid1 == uuid2)
        // UUID format: 8-4-4-4-12 hex chars
        #expect(uuid1.count == 36)
        #expect(uuid1.contains("-"))
    }

    @Test
    func `Different machine info produces different UUID`() {
        let info1 = MachineMetadata.Info(
            cpuBrandString: "Apple M1",
            coreCount: 8,
            modelCode: "MacBookPro18,1",
            ramMegabytes: 16384,
        )
        let info2 = MachineMetadata.Info(
            cpuBrandString: "Apple M2",
            coreCount: 8,
            modelCode: "Mac14,7",
            ramMegabytes: 16384,
        )
        let uuid1 = SetPerformanceBaselineTool.deterministicUUID(from: info1)
        let uuid2 = SetPerformanceBaselineTool.deterministicUUID(from: info2)
        #expect(uuid1 != uuid2)
    }

    // MARK: - Baseline Entry Extraction

    @Test
    func `Entries from metrics extracts class and method`() {
        let metrics = [
            XCResultParser.PerformanceMetricResult(
                testIdentifier: "DOMTests/testSorting()",
                testIdentifierURL: nil,
                testRuns: [
                    XCResultParser.TestRunWithMetrics(
                        testPlanConfiguration: XCResultParser.MetricConfiguration(
                            configurationId: "c1", configurationName: "Config",
                        ),
                        device: XCResultParser.MetricDevice(
                            deviceId: "d1", deviceName: "Mac",
                        ),
                        metrics: [
                            XCResultParser.PerformanceMetric(
                                displayName: "Wall Clock Time",
                                unitOfMeasurement: "s",
                                measurements: [0.040, 0.042],
                                identifier: "com.apple.dt.XCTMetric_Clock.time.monotonic",
                                baselineName: nil,
                                baselineAverage: nil,
                                maxRegression: nil,
                                maxPercentRegression: nil,
                                maxStandardDeviation: nil,
                                maxPercentRelativeStandardDeviation: nil,
                                polarity: nil,
                            ),
                        ],
                    ),
                ],
            ),
        ]

        let entries = SetPerformanceBaselineTool.entriesFromMetrics(metrics)
        #expect(entries.count == 1)
        #expect(entries[0].className == "DOMTests")
        #expect(entries[0].methodName == "testSorting()")
        #expect(entries[0].metricIdentifier == "com.apple.dt.XCTMetric_Clock.time.monotonic")
        #expect(entries[0].baselineAverage == 0.041)
    }

    @Test
    func `Entries from manual parses baseline entries`() throws {
        let manual: [Value] = [
            .object([
                "test_name": .string("MyTests/testFoo()"),
                "metric_identifier": .string("com.apple.dt.XCTMetric_Clock.time.monotonic"),
                "baseline_average": .double(0.5),
                "max_percent_regression": .double(10.0),
            ]),
        ]

        let entries = try SetPerformanceBaselineTool.entriesFromManual(manual)
        #expect(entries.count == 1)
        #expect(entries[0].className == "MyTests")
        #expect(entries[0].methodName == "testFoo()")
        #expect(entries[0].baselineAverage == 0.5)
        #expect(entries[0].maxPercentRegression == 10.0)
    }

    // MARK: - Tool Error Cases

    @Test
    func `GetPerformanceMetricsTool with missing path throws`() async {
        let tool = GetPerformanceMetricsTool()
        do {
            _ = try await tool.execute(arguments: [:])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("required"))
        }
    }

    @Test
    func `GetPerformanceMetricsTool with nonexistent path throws`() async {
        let tool = GetPerformanceMetricsTool()
        do {
            _ = try await tool.execute(arguments: [
                "result_bundle_path": .string("/nonexistent/path.xcresult"),
            ])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("not found"))
        }
    }

    // MARK: - Plist Round-Trip

    @Test
    func `Baseline plist generation produces valid PropertyList`() throws {
        let info = MachineMetadata.Info(
            cpuBrandString: "Apple M1",
            coreCount: 8,
            modelCode: "Mac14,1",
            ramMegabytes: 16384,
        )

        // Build Info.plist content
        let runDestUUID = SetPerformanceBaselineTool.deterministicUUID(from: info)
        let infoPlist: [String: Any] = [
            runDestUUID: [
                "cpuKind": info.cpuBrandString,
                "cpuCount": info.coreCount,
                "modelCode": info.modelCode,
                "physicalRAMAmountInMegabytes": info.ramMegabytes,
            ] as [String: Any],
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0,
        )

        // Verify round-trip
        let decoded = try PropertyListSerialization.propertyList(
            from: data, format: nil,
        )
        let dict = try #require(decoded as? [String: Any])
        let destDict = try #require(dict[runDestUUID] as? [String: Any])
        #expect(destDict["cpuKind"] as? String == "Apple M1")
        #expect(destDict["cpuCount"] as? Int == 8)
    }
}
