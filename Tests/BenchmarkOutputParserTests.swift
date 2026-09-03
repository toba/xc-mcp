import Testing
import Foundation
@testable import XCMCPCore

/// Tests for what the `swift package benchmark` plugin printed.
///
/// The fixtures reproduce the plugin's own output: an influx CSV export for a run, the verdict
/// sentences for a threshold check, and the target blocks for a list.
struct BenchmarkOutputParserTests {
    /// One influx export covering two metrics of one benchmark, at two percentiles each.
    ///
    /// The real export writes all seven percentiles. Two are enough to prove the grouping.
    private static let influx = """
        #datatype tag,tag,tag,tag,tag,tag,tag,tag,tag,double,double,double,long,long,dateTime
        measurement,hostName,processoryType,processors,memory,kernelVersion,metric,unit,test,percentile,value,test_average,iterations,warmup_iterations,time
        TobaCoreBenchmarks,host,Apple-M4,10,32,Darwin,Malloc(total),,AttributedDebugText,50.0,123000,123500,10,1,2026-09-03T00:00:00Z
        TobaCoreBenchmarks,host,Apple-M4,10,32,Darwin,Malloc(total),,AttributedDebugText,90.0,124000,123500,10,1,2026-09-03T00:00:00Z
        TobaCoreBenchmarks,host,Apple-M4,10,32,Darwin,Time(wallclock),μs,AttributedDebugText,50.0,34000000,34500000,10,1,2026-09-03T00:00:00Z
        TobaCoreBenchmarks,host,Apple-M4,10,32,Darwin,Time(wallclock),μs,AttributedDebugText,90.0,34766847,34500000,10,1,2026-09-03T00:00:00Z
        """

    // MARK: - Run figures

    @Test
    func `one row per benchmark and metric`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.count == 2)
        #expect(figures.allSatisfy { $0.target == "TobaCoreBenchmarks" })
        #expect(figures.allSatisfy { $0.benchmark == "AttributedDebugText" })
        #expect(figures.map(\.metric) == ["mallocCountTotal", "wallClock"])
    }

    @Test
    func `a display label maps back to the name the plugin accepts`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.first?.metric == "mallocCountTotal")
        #expect(figures.first?.isTime == false)
        #expect(figures.last?.metric == "wallClock")
        #expect(figures.last?.isTime == true)
    }

    @Test
    func `a figure carries every percentile the export wrote`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.first?.percentiles.map(\.label) == ["p50", "p90"])
        #expect(figures.first?.percentiles.map(\.value) == [123_000, 124_000])
    }

    @Test
    func `the p90 is the figure the gate reads`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.first?.p90 == 124_000)
        #expect(figures.last?.p90 == 34_766_847)
    }

    @Test
    func `a time metric reports nanoseconds whatever unit the export names`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.last?.unit == "ns")
        #expect(figures.first?.unit == "count")
    }

    @Test
    func `the sample and warmup counts come off the row`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)

        #expect(figures.first?.samples == 10)
        #expect(figures.first?.warmups == 1)
    }

    @Test
    func `build output around the export parses to nothing`() {
        let noise = """
            Building for production...
            Build complete!
            [1/2] Compiling TobaCoreBenchmarks
            """

        #expect(BenchmarkOutputParser.figures(from: noise).isEmpty)
    }

    @Test
    func `a run that matched nothing yields no figure`() {
        #expect(BenchmarkOutputParser.figures(from: "").isEmpty)
    }

    @Test
    func `an unknown metric label reaches the report unchanged`() {
        let line = """
            T,host,Apple-M4,10,32,Darwin,MyOwnMetric,,Bench,90.0,7,7,10,1,2026-09-03T00:00:00Z
            """
        let figures = BenchmarkOutputParser.figures(from: line)

        #expect(figures.first?.metric == "MyOwnMetric")
        #expect(figures.first?.isTime == false)
    }

    @Test
    func `the accepted metric names come from the display table`() {
        #expect(
            SwiftRunner
                .benchmarkMetricNames
                == Set(BenchmarkOutputParser.metricDisplayNames.map(\.raw)),
        )
        #expect(SwiftRunner.benchmarkMetricNames.contains("mallocCountTotal"))
    }

    @Test
    func `every display label indexes back to its own metric`() {
        for entry in BenchmarkOutputParser.metricDisplayNames {
            let label = entry.display.filter { !$0.isWhitespace }
            let resolved = BenchmarkOutputParser.metric(forDisplayLabel: label)

            #expect(resolved.raw == entry.raw)
            #expect(resolved.isTime == entry.isTime)
        }
    }

    @Test
    func `a quoted benchmark name stays one field`() {
        let fields = BenchmarkOutputParser.csvFields("a,b,\"one,two\",c")

        #expect(fields == ["a", "b", "one,two", "c"])
    }

    @Test
    func `a whole percentile loses its decimal point`() {
        #expect(BenchmarkOutputParser.percentileLabel("90.0") == "p90")
        #expect(BenchmarkOutputParser.percentileLabel("99.9") == "p99.9")
    }

    // MARK: - Threshold verdict

    @Test
    func `an unchanged check reads as equal`() {
        let output = "The baseline 'current' is EQUAL to the defined thresholds."

        #expect(BenchmarkOutputParser.verdict(from: output) == .equal)
    }

    @Test
    func `a result better than the ceiling reads as an improvement`() {
        let output = """
            The baseline 'current' is BETTER than the defined thresholds.
            error: benchmarkThresholdImprovement
            """

        #expect(BenchmarkOutputParser.verdict(from: output) == .improvement)
    }

    @Test
    func `the plugin error name alone still reads as an improvement`() {
        #expect(
            BenchmarkOutputParser.verdict(
                from: "error: benchmarkThresholdImprovement")
                == .improvement,
        )
    }

    @Test
    func `a result worse than the ceiling reads as a regression`() {
        let output = """
            The baseline 'current' is WORSE than the defined thresholds.
            error: benchmarkThresholdRegression
            """

        #expect(BenchmarkOutputParser.verdict(from: output) == .regression)
    }

    @Test
    func `output holding no comparison yields no verdict`() {
        #expect(BenchmarkOutputParser.verdict(from: "Build complete!") == nil)
    }

    @Test
    func `the plugin error name comes off a failed run`() {
        let output = "error: buildFailed"

        #expect(BenchmarkOutputParser.pluginError(in: output) == "buildFailed")
        #expect(BenchmarkOutputParser.pluginError(in: "Build complete!") == nil)
    }

    // MARK: - Listing

    @Test
    func `a list run yields one entry per target`() {
        let output = """

            Target 'TobaCoreBenchmarks' available benchmarks:
            AttributedDebugText
            AttributedRangeFromNSRange

            Target 'TobaHashBenchmarks' available benchmarks:
            HashOneBlock

            """
        let listings = BenchmarkOutputParser.listings(from: output)

        #expect(listings.count == 2)
        #expect(listings.first?.target == "TobaCoreBenchmarks")
        #expect(
            listings.first?.benchmarks == ["AttributedDebugText", "AttributedRangeFromNSRange"])
        #expect(listings.last?.benchmarks == ["HashOneBlock"])
    }

    @Test
    func `build output before the first header never becomes a name`() {
        let output = """
            Building for production...
            Build complete!

            Target 'TobaCoreBenchmarks' available benchmarks:
            OneBenchmark

            """
        let listings = BenchmarkOutputParser.listings(from: output)

        #expect(listings.count == 1)
        #expect(listings.first?.benchmarks == ["OneBenchmark"])
    }

    @Test
    func `a suite that reported nothing yields no listing`() {
        #expect(BenchmarkOutputParser.listings(from: "Build complete!").isEmpty)
    }

    // MARK: - Formatting

    @Test
    func `a run report leads with the p90 of every metric`() {
        let figures = BenchmarkOutputParser.figures(from: Self.influx)
        let text = BenchmarkResultFormatter.formatRun(
            figures: figures, context: "toba-core", elapsed: .seconds(35),
        )

        #expect(text.contains("### p90"))
        #expect(text.contains(
            "| TobaCoreBenchmarks:AttributedDebugText | mallocCountTotal | 124000"))
        #expect(text.contains("2 figures"))
        #expect(text.contains("1 benchmark,"))
    }

    @Test
    func `a check report names the verdict and what it means`() {
        let text = BenchmarkResultFormatter.formatCheck(
            verdict: .improvement, deviations: nil, context: "toba-core", elapsed: .seconds(12),
        )

        #expect(text.contains("verdict: improvement"))
        #expect(text.contains("names a win rather than a failure"))
    }

    @Test
    func `the deviation tables come out of a check run`() {
        let output = """
            ================================================
            Deviations worse than threshold for Target:Bench
            ================================================

            Malloc (total) | p90 | 100 | 120
            The baseline 'current' is WORSE than the defined thresholds.
            error: benchmarkThresholdRegression
            """
        let section = BenchmarkResultFormatter.deviations(from: output)

        #expect(section?.contains("Deviations worse than threshold") == true)
        #expect(section?.contains("Malloc (total)") == true)
        #expect(section?.contains("error:") == false)
        #expect(section?.contains("defined thresholds") == false)
    }

    @Test
    func `output with no deviation section yields none`() {
        let output = "The baseline 'current' is EQUAL to the defined thresholds."

        #expect(BenchmarkResultFormatter.deviations(from: output) == nil)
    }
}
