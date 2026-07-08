import Foundation

public extension Duration {
    /// A compact human-readable rendering of a wall-clock duration for tool result lines.
    ///
    /// Under a minute it reads as seconds with one decimal (e.g. `12.4s`); longer spans switch to
    /// `XmYs` (e.g. `5m3s`). Used to surface elapsed build/test/clean time so callers can spot
    /// regressions without wrapping each MCP call in shell timing.
    var elapsedDescription: String {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let mins = Int(seconds) / 60
        let secs = Int(seconds.rounded()) % 60
        return "\(mins)m\(secs)s"
    }
}
