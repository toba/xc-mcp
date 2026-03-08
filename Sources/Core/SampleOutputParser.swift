import Foundation

/// Parses macOS `sample` command output into structured, agent-friendly summaries.
///
/// Extracts call graph trees, filters idle/waiting frames, aggregates by function,
/// and produces sorted summaries of heaviest call paths.
public enum SampleOutputParser {
    // MARK: - Public API

    /// Parses raw `sample` output and returns a summarized, agent-friendly report.
    ///
    /// - Parameters:
    ///   - rawOutput: The full text output from `/usr/bin/sample`.
    ///   - filter: `"app"` (default) to show only app-code frames, `"all"` for everything.
    ///   - topN: Number of heaviest functions/paths to return (default 20).
    ///   - thread: `"main"` (default), `"all"`, or a specific thread name.
    /// - Returns: A formatted summary string.
    public static func summarize(
        rawOutput: String,
        filter: String = "app",
        topN: Int = 20,
        thread: String = "main",
    ) -> String {
        let sections = splitSections(rawOutput)
        let header = sections.header
        let appBinary = extractAppBinary(from: sections.binaryImages, header: header)
        let threads = parseCallGraph(sections.callGraph)

        // Filter threads
        let selectedThreads: [ThreadSample]
        switch thread {
            case "main":
                selectedThreads = threads.filter(\.isMainThread)
            case "all":
                selectedThreads = threads
            default:
                selectedThreads = threads.filter {
                    $0.name.localizedCaseInsensitiveContains(thread)
                }
        }

        guard !selectedThreads.isEmpty else {
            return "No matching threads found for filter '\(thread)'.\n\n"
                + "Available threads:\n"
                + threads.map { "  - \($0.name) (\($0.totalSamples) samples)" }
                .joined(separator: "\n")
        }

        let filterApp = filter != "all"

        var result = ""
        result += formatHeader(header)

        // Per-thread summary
        result += "\n## Thread Summary\n\n"
        for t in threads {
            let status = isThreadIdle(t) ? "idle" : "active"
            result += "  \(t.name): \(t.totalSamples) samples (\(status))\n"
        }

        // Heaviest functions (from leaf frames)
        let allLeaves = selectedThreads.flatMap { collectLeafFrames($0.root) }
        let aggregated = aggregateFrames(
            allLeaves, filterApp: filterApp, appBinary: appBinary,
        )
        let topFunctions = Array(aggregated.prefix(topN))

        if !topFunctions.isEmpty {
            result += "\n## Heaviest Functions\n\n"
            result += formatFunctionTable(topFunctions)
        }

        // Heaviest call paths through app code
        let paths = selectedThreads.flatMap {
            collectHeaviestPaths($0.root, filterApp: filterApp, appBinary: appBinary)
        }
        let sortedPaths = paths.sorted { $0.samples > $1.samples }
        let topPaths = Array(sortedPaths.prefix(topN))

        if !topPaths.isEmpty {
            result += "\n## Heaviest Call Paths\n\n"
            for path in topPaths {
                result += "  \(path.samples) samples: \(path.path)\n"
            }
        }

        return result
    }

    // MARK: - Data types

    struct ThreadSample {
        let name: String
        let totalSamples: Int
        let isMainThread: Bool
        let root: [FrameNode]
    }

    struct FrameNode {
        let function: String
        let library: String
        let samples: Int
        var children: [FrameNode]
    }

    struct FunctionAggregate {
        let function: String
        let library: String
        var samples: Int
    }

    struct CallPath {
        let path: String
        let samples: Int
    }

    struct Sections {
        var header: String = ""
        var callGraph: String = ""
        var binaryImages: String = ""
    }

    // MARK: - Section splitting

    static func splitSections(_ raw: String) -> Sections {
        var sections = Sections()

        let callGraphMarker = "Call graph:"
        let sortByMarker = "Total number in stack"
        let binaryImagesMarker = "Binary Images:"

        guard let callGraphRange = raw.range(of: callGraphMarker) else {
            sections.header = raw
            return sections
        }

        sections.header = String(raw[raw.startIndex ..< callGraphRange.lowerBound])

        let afterCallGraph = raw[callGraphRange.lowerBound...]
        let endOfCallGraph: String.Index
        if let sortRange = afterCallGraph.range(of: sortByMarker) {
            endOfCallGraph = sortRange.lowerBound
        } else if let binaryRange = afterCallGraph.range(of: binaryImagesMarker) {
            endOfCallGraph = binaryRange.lowerBound
        } else {
            endOfCallGraph = raw.endIndex
        }

        sections.callGraph = String(raw[callGraphRange.lowerBound ..< endOfCallGraph])

        if let binaryRange = raw.range(of: binaryImagesMarker) {
            sections.binaryImages = String(raw[binaryRange.lowerBound...])
        }

        return sections
    }

    // MARK: - Call graph parsing

    static func parseCallGraph(_ text: String) -> [ThreadSample] {
        let lines = text.components(separatedBy: .newlines)
        var threads: [ThreadSample] = []
        var currentFrames: [(depth: Int, function: String, library: String, samples: Int)] = []
        var currentThreadHeader = ""
        var currentThreadSamples = 0

        for line in lines {
            if line.hasPrefix("Call graph:") { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Thread header: "    1000 Thread_100   DispatchQueue_1: ..."
            if let match = trimmed.wholeMatch(of: /^(\d+)\s+(Thread_\S+.*)$/) {
                if !currentThreadHeader.isEmpty {
                    let nodes = buildTree(from: currentFrames)
                    threads.append(ThreadSample(
                        name: currentThreadHeader,
                        totalSamples: currentThreadSamples,
                        isMainThread: currentThreadHeader.contains("main-thread")
                            || currentThreadHeader.contains("main thread"),
                        root: nodes,
                    ))
                }
                currentThreadSamples = Int(match.1) ?? 0
                currentThreadHeader = String(match.2)
                currentFrames = []
                continue
            }

            // Frame line
            let depth = countPlusDepth(line)
            if let parsed = parseFrameLine(line) {
                currentFrames.append((
                    depth: depth,
                    function: parsed.function,
                    library: parsed.library,
                    samples: parsed.samples,
                ))
            }
        }

        // Save last thread
        if !currentThreadHeader.isEmpty {
            let nodes = buildTree(from: currentFrames)
            threads.append(ThreadSample(
                name: currentThreadHeader,
                totalSamples: currentThreadSamples,
                isMainThread: currentThreadHeader.contains("main-thread")
                    || currentThreadHeader.contains("main thread"),
                root: nodes,
            ))
        }

        return threads
    }

    /// Determines nesting depth from indentation.
    ///
    /// In `sample` output, each frame line has one `+` and the depth is indicated
    /// by the column position of the first digit (the sample count). Each depth
    /// level adds 2 characters of indentation after the `+`.
    static func countPlusDepth(_ line: String) -> Int {
        // Find the column of the first digit character
        var col = 0
        for ch in line {
            if ch.isNumber { break }
            col += 1
        }
        // Depth 0 = no +; depth 1 starts around col 6; each level adds 2
        // Normalize: subtract the base offset and divide by 2
        return max(0, col / 2)
    }

    static func parseFrameLine(_ line: String)
        -> (function: String, library: String, samples: Int)?
    {
        // Strip leading tree-drawing characters: whitespace, +, |, !, :
        var startIndex = line.startIndex
        for ch in line {
            if ch == " " || ch == "+" || ch == "|" || ch == "!" || ch == ":" {
                startIndex = line.index(after: startIndex)
            } else {
                break
            }
        }
        let trimmed = line[startIndex...]

        guard let match = trimmed.wholeMatch(of: /(\d+)\s+(.+?)\s+\(in\s+(.+?)\).*$/) else {
            return nil
        }

        return (
            function: String(match.2),
            library: String(match.3),
            samples: Int(match.1) ?? 0,
        )
    }

    /// Builds a tree from flat frames with depth information.
    /// Uses a stack to track the current path through the tree.
    static func buildTree(
        from frames: [(depth: Int, function: String, library: String, samples: Int)],
    ) -> [FrameNode] {
        guard !frames.isEmpty else { return [] }

        // We'll build iteratively using an index-path stack.
        // Each stack entry is: (depth, pointer into the tree)
        // To avoid value-type mutation issues, build as a flat list then assemble.

        struct FlatEntry {
            let function: String
            let library: String
            let samples: Int
            let depth: Int
            var childIndices: [Int]
        }

        var entries: [FlatEntry] = []
        entries.reserveCapacity(frames.count)
        // Stack of (depth, entryIndex) for finding parent
        var stack: [(depth: Int, entryIndex: Int)] = []
        var rootIndices: [Int] = []

        for frame in frames {
            let idx = entries.count
            entries.append(FlatEntry(
                function: frame.function,
                library: frame.library,
                samples: frame.samples,
                depth: frame.depth,
                childIndices: [],
            ))

            // Pop stack until we find a parent with strictly lower depth
            while let last = stack.last, last.depth >= frame.depth {
                stack.removeLast()
            }

            if let parent = stack.last {
                entries[parent.entryIndex].childIndices.append(idx)
            } else {
                rootIndices.append(idx)
            }

            stack.append((depth: frame.depth, entryIndex: idx))
        }

        // Convert flat entries to tree nodes (bottom-up)
        func toNode(_ index: Int) -> FrameNode {
            let entry = entries[index]
            return FrameNode(
                function: entry.function,
                library: entry.library,
                samples: entry.samples,
                children: entry.childIndices.map { toNode($0) },
            )
        }

        return rootIndices.map { toNode($0) }
    }

    // MARK: - Filtering

    /// Known idle/waiting functions to filter out.
    static let idleFunctions: Set<String> = [
        "mach_msg_trap", "mach_msg2_trap", "__psynch_cvwait", "kevent",
        "__semwait_signal", "__workq_kernreturn", "mach_msg",
        "mach_msg_overwrite", "mach_msg2_internal",
        "__CFRunLoopServiceMachPort", "CFRunLoopRunSpecific",
        "__CFRunLoopRun", "_DPSNextEvent", "ReceiveNextEventCommon",
        "RunCurrentEventLoopInMode", "_BlockUntilNextEventMatchingListInModeWithFilter",
        "_pthread_wqthread", "start_wqthread", "thread_start",
        "_NSEventThread",
    ]

    /// Known system library prefixes — filtered in "app" mode.
    static let systemLibraryPrefixes: [String] = [
        "libsystem_", "libdispatch", "libobjc", "libdyld", "libc++",
        "libxpc", "CoreFoundation", "Foundation", "AppKit", "UIKit",
        "SwiftUI", "HIToolbox", "dyld", "libswiftCore", "libswiftDispatch",
        "libswift", "libpthread", "Metal",
    ]

    static func isIdleFunction(_ name: String) -> Bool {
        idleFunctions.contains(name)
    }

    static func isSystemLibrary(_ library: String) -> Bool {
        systemLibraryPrefixes.contains { library.hasPrefix($0) }
    }

    static func isAppFrame(_ library: String, appBinary: String?) -> Bool {
        if let appBinary {
            return library == appBinary || !isSystemLibrary(library)
        }
        return !isSystemLibrary(library)
    }

    static func isThreadIdle(_ thread: ThreadSample) -> Bool {
        let leaves = collectLeafFrames(thread.root)
        return leaves.allSatisfy { isIdleFunction($0.function) }
    }

    static func collectLeafFrames(_ nodes: [FrameNode]) -> [FrameNode] {
        var result: [FrameNode] = []
        var stack = nodes
        while let node = stack.popLast() {
            if node.children.isEmpty {
                result.append(node)
            } else {
                stack.append(contentsOf: node.children)
            }
        }
        return result
    }

    // MARK: - Aggregation

    static func aggregateFrames(
        _ frames: [FrameNode],
        filterApp: Bool,
        appBinary: String?,
    ) -> [FunctionAggregate] {
        var map: [String: FunctionAggregate] = [:]

        for frame in frames {
            if isIdleFunction(frame.function) { continue }
            if filterApp, !isAppFrame(frame.library, appBinary: appBinary) { continue }

            let key = "\(frame.function)|\(frame.library)"
            if var existing = map[key] {
                existing.samples += frame.samples
                map[key] = existing
            } else {
                map[key] = FunctionAggregate(
                    function: frame.function,
                    library: frame.library,
                    samples: frame.samples,
                )
            }
        }

        return map.values.sorted { $0.samples > $1.samples }
    }

    // MARK: - Call paths

    static func collectHeaviestPaths(
        _ nodes: [FrameNode],
        filterApp: Bool,
        appBinary: String?,
    ) -> [CallPath] {
        var result: [CallPath] = []

        func walk(_ node: FrameNode, path: [String]) {
            let include: Bool
            if filterApp {
                include = isAppFrame(node.library, appBinary: appBinary)
            } else {
                include = true
            }

            let currentPath: [String]
            if include, !isIdleFunction(node.function), node.function != "???" {
                currentPath = path + [node.function]
            } else {
                currentPath = path
            }

            if node.children.isEmpty {
                if !currentPath.isEmpty {
                    result.append(CallPath(
                        path: currentPath.joined(separator: " → "),
                        samples: node.samples,
                    ))
                }
            } else {
                for child in node.children {
                    walk(child, path: currentPath)
                }
            }
        }

        for node in nodes {
            walk(node, path: [])
        }

        // Merge identical paths
        var pathMap: [String: Int] = [:]
        for p in result {
            pathMap[p.path, default: 0] += p.samples
        }

        return pathMap.map { CallPath(path: $0.key, samples: $0.value) }
    }

    // MARK: - Formatting

    static func formatHeader(_ header: String) -> String {
        var result = "## Process Info\n\n"
        let lines = header.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "----" { continue }
            if trimmed.hasPrefix("Analysis of sampling") || trimmed.contains(":") {
                result += "  \(trimmed)\n"
            }
        }
        return result
    }

    static func formatFunctionTable(_ functions: [FunctionAggregate]) -> String {
        guard !functions.isEmpty else { return "" }

        let maxSamples = functions.map { String($0.samples).count }.max() ?? 5
        let samplesWidth = max(maxSamples, 7)

        let maxFunc = min(functions.map(\.function.count).max() ?? 30, 60)
        let funcWidth = max(maxFunc, 8)

        var result = ""
        result += "  \(pad("Samples", width: samplesWidth)) | \(pad("Function", width: -funcWidth)) | Library\n"
        result += "  \(String(repeating: "-", count: samplesWidth))-+-\(String(repeating: "-", count: funcWidth))-+------------------\n"

        for fn in functions {
            let funcName =
                fn.function.count > funcWidth
                    ? String(fn.function.prefix(funcWidth - 3)) + "..."
                    : fn.function
            result += "  \(pad(String(fn.samples), width: samplesWidth)) | \(pad(funcName, width: -funcWidth)) | \(fn.library)\n"
        }

        return result
    }

    /// Pads a string to the given width. Positive width = right-aligned, negative = left-aligned.
    private static func pad(_ string: String, width: Int) -> String {
        let count = string.count
        let absWidth = abs(width)
        guard count < absWidth else { return string }
        let padding = String(repeating: " ", count: absWidth - count)
        return width >= 0 ? padding + string : string + padding
    }

    // MARK: - Binary image extraction

    static func extractAppBinary(from binaryImages: String, header: String) -> String? {
        if let match = header.firstMatch(of: /Process:\s+(\S+)/) {
            return String(match.1)
        }
        let lines = binaryImages.components(separatedBy: .newlines)
        for line in lines where line.contains("+") {
            if let match = line.firstMatch(of: /\+(\S+)\s+\(/) {
                return String(match.1)
            }
        }
        return nil
    }
}
