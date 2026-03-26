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

    // MARK: - ShowPerformanceBaselinesTool Formatting

    @Test
    func `Human metric name maps known identifiers`() {
        let name = ShowPerformanceBaselinesTool.humanMetricName(
            "com.apple.dt.XCTMetric_Clock.time.monotonic",
        )
        #expect(name == "Clock Monotonic Time")
    }

    @Test
    func `Human metric name returns identifier for unknown`() {
        let name = ShowPerformanceBaselinesTool.humanMetricName("custom.metric.id")
        #expect(name == "custom.metric.id")
    }

    @Test
    func `Format value for time metrics`() {
        let short = ShowPerformanceBaselinesTool.formatValue(
            0.037, metricId: "com.apple.dt.XCTMetric_Clock.time.monotonic",
        )
        #expect(short == "0.0370s")

        let long = ShowPerformanceBaselinesTool.formatValue(
            1.234, metricId: "com.apple.dt.XCTMetric_Clock.time.monotonic",
        )
        #expect(long == "1.234s")
    }

    @Test
    func `Format value for memory metrics`() {
        let kb = ShowPerformanceBaselinesTool.formatValue(
            15400, metricId: "com.apple.dt.XCTMetric_Memory.physical_peak",
        )
        #expect(kb == "15400 kB")

        let gb = ShowPerformanceBaselinesTool.formatValue(
            2_500_000, metricId: "com.apple.dt.XCTMetric_Memory.physical",
        )
        #expect(gb == "2.5 GB")

        let bytes = ShowPerformanceBaselinesTool.formatValue(
            512, metricId: "com.apple.dt.XCTMetric_Memory.physical",
        )
        #expect(bytes == "512 bytes")
    }

    @Test
    func `Format percent integer and decimal`() {
        #expect(ShowPerformanceBaselinesTool.formatPercent(10.0) == "10%")
        #expect(ShowPerformanceBaselinesTool.formatPercent(5.5) == "5.5%")
    }

    @Test
    func `Show baselines with nonexistent project returns error`() async {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)
        do {
            _ = try await tool.execute(arguments: [
                "project_path": .string("/nonexistent/Project.xcodeproj"),
            ])
            Issue.record("Expected MCPError to be thrown")
        } catch {
            #expect(String(describing: error).contains("not found"))
        }
    }

    @Test
    func `Show baselines with no baselines dir returns message`() async throws {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)

        // Create a temporary xcodeproj with no xcbaselines
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-show-baselines-\(UUID().uuidString)")
        let projDir = tempDir.appendingPathComponent("Test.xcodeproj")
        try FileManager.default.createDirectory(
            at: projDir, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await tool.execute(arguments: [
            "project_path": .string(projDir.path),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.contains("does not exist"))
    }

    @Test
    func `Show baselines reads written baseline data`() async throws {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)

        // Create a temporary xcodeproj with xcbaselines
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-show-baselines-\(UUID().uuidString)")
        let projDir = tempDir.appendingPathComponent("Test.xcodeproj")
        let targetUUID = "AABBCCDD00112233AABBCCDD"
        let baselineDir = projDir
            .appendingPathComponent("xcshareddata/xcbaselines/\(targetUUID).xcbaseline")
        try FileManager.default.createDirectory(
            at: baselineDir, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Write a pbxproj with a target
        let pbxproj = """
        // !$*UTF8*$!
        {
            objects = {
                \(targetUUID) /* MyTests */ = {
                    isa = PBXNativeTarget;
                    name = MyTests;
                };
            };
        }
        """
        try pbxproj.write(
            to: projDir.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8,
        )

        // Write Info.plist
        let runDestUUID = "11111111-2222-3333-4444-555555555555"
        let infoPlist: [String: Any] = [
            runDestUUID: [
                "cpuKind": "Apple M1 Max",
                "cpuCount": 10,
                "modelCode": "Mac13,1",
                "physicalRAMAmountInMegabytes": 65536,
            ] as [String: Any],
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist, format: .xml, options: 0,
        )
        try infoData.write(to: baselineDir.appendingPathComponent("Info.plist"))

        // Write run-destination plist
        let baselinePlist: [String: Any] = [
            "classNames": [
                "DocumentRenderPerformanceTests": [
                    "testConcurrentRenderPerformance()": [
                        "com.apple.dt.XCTMetric_Clock.time.monotonic": [
                            "baselineAverage": 0.037,
                            "maxPercentRegression": 10.0,
                        ] as [String: Any],
                        "com.apple.dt.XCTMetric_Memory.physical": [
                            "baselineAverage": 154.0,
                            "maxPercentRegression": 10.0,
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let baselineData = try PropertyListSerialization.data(
            fromPropertyList: baselinePlist, format: .xml, options: 0,
        )
        try baselineData.write(
            to: baselineDir.appendingPathComponent("\(runDestUUID).plist"),
        )

        let result = try await tool.execute(arguments: [
            "project_path": .string(projDir.path),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }

        #expect(text.contains("MyTests Baselines"))
        #expect(text.contains("Apple M1 Max"))
        #expect(text.contains("DocumentRenderPerformanceTests"))
        #expect(text.contains("testConcurrentRenderPerformance()"))
        #expect(text.contains("Clock Monotonic Time"))
        #expect(text.contains("0.0370s"))
        #expect(text.contains("max regression: 10%"))
    }

    @Test
    func `Show baselines with target filter excludes other targets`() async throws {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-show-baselines-filter-\(UUID().uuidString)")
        let projDir = tempDir.appendingPathComponent("Test.xcodeproj")
        let uuid1 = "AABBCCDD00112233AABBCCDD"
        let uuid2 = "DDEEFF0011223344DDEEFF00"
        let baselineDir1 = projDir
            .appendingPathComponent("xcshareddata/xcbaselines/\(uuid1).xcbaseline")
        let baselineDir2 = projDir
            .appendingPathComponent("xcshareddata/xcbaselines/\(uuid2).xcbaseline")
        try FileManager.default.createDirectory(
            at: baselineDir1, withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: baselineDir2, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pbxproj = """
        // !$*UTF8*$!
        {
            objects = {
                \(uuid1) /* TargetA */ = {
                    isa = PBXNativeTarget;
                    name = TargetA;
                };
                \(uuid2) /* TargetB */ = {
                    isa = PBXNativeTarget;
                    name = TargetB;
                };
            };
        }
        """
        try pbxproj.write(
            to: projDir.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8,
        )

        let runDestUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let infoPlist: [String: Any] = [
            runDestUUID: [
                "cpuKind": "Apple M2",
                "cpuCount": 8,
                "modelCode": "Mac14,7",
                "physicalRAMAmountInMegabytes": 16384,
            ] as [String: Any],
        ]

        let baselinePlist: [String: Any] = [
            "classNames": [
                "TestClass": [
                    "testMethod()": [
                        "com.apple.dt.XCTMetric_Clock.time.monotonic": [
                            "baselineAverage": 1.0,
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]

        for dir in [baselineDir1, baselineDir2] {
            let infoData = try PropertyListSerialization.data(
                fromPropertyList: infoPlist, format: .xml, options: 0,
            )
            try infoData.write(to: dir.appendingPathComponent("Info.plist"))
            let baselineData = try PropertyListSerialization.data(
                fromPropertyList: baselinePlist, format: .xml, options: 0,
            )
            try baselineData.write(
                to: dir.appendingPathComponent("\(runDestUUID).plist"),
            )
        }

        let result = try await tool.execute(arguments: [
            "project_path": .string(projDir.path),
            "target_name": .string("TargetA"),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }

        #expect(text.contains("TargetA Baselines"))
        #expect(!text.contains("TargetB"))
    }

    @Test
    func `Parse real Xcode xcbaseline fixture`() async throws {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)

        // Set up a temp project using the real fixture
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-show-baselines-real-\(UUID().uuidString)")
        let projDir = tempDir.appendingPathComponent("Thesis.xcodeproj")
        let baselinesDir = projDir.appendingPathComponent("xcshareddata/xcbaselines")
        try FileManager.default.createDirectory(
            at: baselinesDir, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Copy the real fixture
        let fixtureDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/xcbaselines/966E72D22C1A222900AADDBD.xcbaseline")
        let destDir = baselinesDir
            .appendingPathComponent("966E72D22C1A222900AADDBD.xcbaseline")
        try FileManager.default.copyItem(at: fixtureDir, to: destDir)

        // Write a pbxproj so the UUID maps to a target name
        let pbxproj = """
        // !$*UTF8*$!
        {
            objects = {
                966E72D22C1A222900AADDBD /* ThesisTests */ = {
                    isa = PBXNativeTarget;
                    name = ThesisTests;
                };
            };
        }
        """
        try pbxproj.write(
            to: projDir.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8,
        )

        let result = try await tool.execute(arguments: [
            "project_path": .string(projDir.path),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }

        // Verify real Xcode format parsed correctly
        #expect(text.contains("ThesisTests Baselines"))
        #expect(text.contains("Apple M1 Max"))
        #expect(text.contains("ZoteroAttachmentPerformance"))
        #expect(text.contains("testDecodeSampleItems()"))
        #expect(text.contains("CPU Time"))
        #expect(text.contains("Memory Peak Physical"))
    }

    @Test
    func `Show baselines with metric filter narrows output`() async throws {
        let sessionManager = SessionManager()
        let tool = ShowPerformanceBaselinesTool(sessionManager: sessionManager)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-show-baselines-metric-\(UUID().uuidString)")
        let projDir = tempDir.appendingPathComponent("Test.xcodeproj")
        let targetUUID = "AABBCCDD00112233AABBCCDD"
        let baselineDir = projDir
            .appendingPathComponent("xcshareddata/xcbaselines/\(targetUUID).xcbaseline")
        try FileManager.default.createDirectory(
            at: baselineDir, withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pbxproj = """
        // !$*UTF8*$!
        {
            objects = {
                \(targetUUID) /* Tests */ = {
                    isa = PBXNativeTarget;
                    name = Tests;
                };
            };
        }
        """
        try pbxproj.write(
            to: projDir.appendingPathComponent("project.pbxproj"),
            atomically: true, encoding: .utf8,
        )

        let runDestUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let infoPlist: [String: Any] = [
            runDestUUID: ["cpuKind": "M1", "cpuCount": 8,
                          "modelCode": "Mac14,1",
                          "physicalRAMAmountInMegabytes": 16384] as [String: Any],
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist, format: .xml, options: 0,
        )
        try infoData.write(to: baselineDir.appendingPathComponent("Info.plist"))

        let baselinePlist: [String: Any] = [
            "classNames": [
                "PerfTests": [
                    "testSpeed()": [
                        "com.apple.dt.XCTMetric_Clock.time.monotonic": [
                            "baselineAverage": 0.5,
                        ] as [String: Any],
                        "com.apple.dt.XCTMetric_Memory.physical": [
                            "baselineAverage": 1024.0,
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]
        let baselineData = try PropertyListSerialization.data(
            fromPropertyList: baselinePlist, format: .xml, options: 0,
        )
        try baselineData.write(
            to: baselineDir.appendingPathComponent("\(runDestUUID).plist"),
        )

        let result = try await tool.execute(arguments: [
            "project_path": .string(projDir.path),
            "metric_filter": .string("memory"),
        ])

        guard case let .text(text, _, _) = result.content.first else {
            Issue.record("Expected text content")
            return
        }

        #expect(text.contains("Memory Physical"))
        #expect(!text.contains("Clock Monotonic"))
    }
}
