import Foundation

/// Turns parsed benchmark output into the text a tool returns
public enum BenchmarkResultFormatter {
    /// The rule a `filter` or `skip` pattern follows
    ///
    /// The plugin matches a pattern against the whole name and exits 0 when nothing matches, so a
    /// bare prefix reads as a clean pass. The schema, the list report and the empty-result error
    /// all say this, and they read it from here so no copy drifts.
    public static let wholeMatchNote =
        "A `filter` value is a regex the whole name must match, so `Observation` selects nothing "
        + "when the names are `ObservationStart` and `ObservationWrite`. Write `Observation.*` to "
        + "select the family."

    /// The sentence every run report carries, so a reader knows what the figures count
    static let unitNote =
        "Figures are raw, which is what a threshold file records: a time metric counts nanoseconds "
        + "and every other metric counts occurrences. `thresholds check` compares p90 alone."

    /// Builds the report for a completed run.
    ///
    /// The p90 table leads, because p90 is the figure the gate reads and the one a before-and-after
    /// comparison turns on. The per-benchmark tables follow with every percentile.
    ///
    /// - Parameters:
    ///   - figures: The figures the run reported.
    ///   - context: What ran, such as `toba-core (the nested Benchmarks package), default traits`.
    ///   - elapsed: How long the command took.
    /// - Returns: The report text.
    public static func formatRun(
        figures: [BenchmarkFigure],
        context: String,
        elapsed: Duration,
    ) -> String {
        let benchmarks = Set(figures.map { "\($0.target):\($0.benchmark)" }).count
        var text = "## Benchmark run\n\n"
        text += "\(context)\n"
        text += "\(benchmarks) benchmark\(benchmarks == 1 ? "" : "s"), "
        text += "\(figures.count) figure\(figures.count == 1 ? "" : "s"), "
        text += "\(elapsed.elapsedDescription)\n\n"
        text += "\(unitNote)\n\n"

        text += "### p90\n\n"
        text += "| Benchmark | Metric | p90 | Unit |\n|---|---|---:|---|\n"

        for figure in figures {
            let p90 = figure.p90.map { String($0) } ?? "n/a"
            text += "| \(figure.target):\(figure.benchmark) | \(figure.metric) | \(p90) "
            text += "| \(figure.unit) |\n"
        }

        for group in grouped(figures) {
            text += "\n### \(group.key)\n\n"
            let samples = group.figures.first?.samples ?? 0
            let warmups = group.figures.first?.warmups ?? 0
            text += "\(samples) sample\(samples == 1 ? "" : "s"), "
            text += "\(warmups) warmup\(warmups == 1 ? "" : "s")\n\n"
            text += percentileTable(group.figures)
        }
        return text
    }

    /// Builds the report for a `thresholds check` run.
    ///
    /// - Parameters:
    ///   - verdict: What the check decided, or `nil` when it reached no comparison.
    ///   - deviations: The plugin's own deviation tables, or `nil` when nothing moved.
    ///   - context: What ran.
    ///   - elapsed: How long the command took.
    /// - Returns: The report text.
    public static func formatCheck(
        verdict: BenchmarkThresholdVerdict?,
        deviations: String?,
        context: String,
        elapsed: Duration,
    ) -> String {
        var text = "## Threshold check\n\n"
        text += "\(context)\n"
        text += "verdict: \(verdict?.rawValue ?? "unknown")\n"
        text += "\(elapsed.elapsedDescription)\n\n"
        text += "\(explanation(of: verdict))\n"
        if let deviations, !deviations.isEmpty { text += "\n```\n\(deviations)\n```\n" }
        return text
    }

    /// Builds the report for a `benchmark list` run.
    ///
    /// - Parameters:
    ///   - listings: One entry per target.
    ///   - context: What ran.
    /// - Returns: The report text.
    public static func formatList(listings: [BenchmarkListing], context: String) -> String {
        var text = "## Benchmarks\n\n\(context)\n\n"

        for listing in listings {
            text += "### \(listing.target) (\(listing.benchmarks.count))\n\n"
            for name in listing.benchmarks { text += "- \(name)\n" }
            text += "\n"
        }
        text += "\(wholeMatchNote)\n"
        return text
    }

    /// The sentence that says what a verdict means and what to do about it
    static func explanation(of verdict: BenchmarkThresholdVerdict?) -> String {
        switch verdict {
            case .equal: "Every figure matches its recorded ceiling."
            case .improvement:
                "A figure beat its recorded ceiling. The plugin prints this as "
                    + "`error: benchmarkThresholdImprovement`, which names a win rather than a "
                    + "failure. Run `thresholds_update` to record it, but only when the change was "
                    + "meant to move the figure."
            case .regression:
                "A figure exceeded its recorded ceiling. Read the deviation table below for the "
                    + "benchmark, the metric and the delta."
            case nil:
                "The check reached no comparison. A benchmark with no threshold file passes "
                    + "silently, so confirm that `Thresholds/` holds a file for each benchmark the "
                    + "filter selected."
        }
    }

    /// Extracts the plugin's deviation tables from a check run.
    ///
    /// - Parameter output: The command's combined output.
    /// - Returns: The tables, or `nil` when the output holds none.
    public static func deviations(from output: String) -> String? {
        let lines = TerminalEscapes.stripped(output).split(
            separator: "\n", omittingEmptySubsequences: false,
        )
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("Deviations ")
        }) else { return nil }

        let kept = lines[start...].filter { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            return !text.hasPrefix("error:") && !text.contains("the defined thresholds")
        }
        let section = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? nil : section
    }

    // MARK: - Tables

    /// One benchmark's figures, keyed by `target:name`
    private struct Group {
        let key: String
        let figures: [BenchmarkFigure]
    }

    /// Groups the figures by benchmark, keeping the order the run reported.
    private static func grouped(_ figures: [BenchmarkFigure]) -> [Group] {
        var order: [String] = []
        var byKey: [String: [BenchmarkFigure]] = [:]

        for figure in figures {
            let key = "\(figure.target):\(figure.benchmark)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(figure)
        }
        return order.map { Group(key: $0, figures: byKey[$0] ?? []) }
    }

    /// Builds one markdown table holding every percentile of every metric in `figures`.
    private static func percentileTable(_ figures: [BenchmarkFigure]) -> String {
        guard let labels = figures.first?.percentiles.map(\.label) else { return "" }
        var text = "| Metric | Unit | \(labels.joined(separator: " | ")) |\n"
        text += "|---|---|\(String(repeating: "---:|", count: labels.count))\n"

        for figure in figures {
            let values = figure.percentiles.map { String($0.value) }.joined(separator: " | ")
            text += "| \(figure.metric) | \(figure.unit) | \(values) |\n"
        }
        return text
    }
}
