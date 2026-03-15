---
# k6n-zr5
title: Add tool to extract and query Swift module symbol graphs
status: in-progress
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-15T17:55:10Z
updated_at: 2026-03-15T17:56:05Z
sync:
    github:
        issue_number: "218"
        synced_at: "2026-03-15T18:09:24Z"
---

## Problem

When an agent needs to discover the public API of a system framework or SPM module (e.g. \"what's the Swift Testing skip API?\"), the only options are web search or reading source files. System frameworks have no source to read, and web search is slow and unreliable for API surface questions.

During a Thesis session, the agent attempted \`xcrun swift-symbolgraph-extract\` manually but it requires multi-step setup (creating output dirs, resolving SDK paths, parsing JSON output) and ultimately failed. The agent fell back to web search to answer a simple question: \"does Swift Testing export a type named SkipInfo or TestSkipped?\"

## Proposed Tool

A \`swift_symbols\` (or \`inspect_module\`) tool that wraps \`xcrun swift-symbolgraph-extract\` and provides filtered, queryable output.

### Inputs

- \`module\` (required): Module name (e.g. \`Testing\`, \`SwiftUI\`, \`Foundation\`)
- \`query\` (optional): Filter symbols by name pattern (e.g. \`skip\`, \`Known\`)
- \`kind\` (optional): Filter by symbol kind (\`struct\`, \`func\`, \`enum\`, \`protocol\`, etc.)
- \`platform\` (optional): Target platform, defaults to macOS
- \`sdk\` (optional): SDK path override, defaults to \`xcrun --show-sdk-path\`

### Output

Filtered list of matching symbols with:
- Fully qualified name
- Kind (struct, func, enum, etc.)
- Declaration snippet (function signature, struct definition)
- Availability annotations if present

### Implementation Notes

- Use \`xcrun swift-symbolgraph-extract -module-name <module> -target <triple> -sdk <sdk> -output-dir <tmpdir>\`
- Parse the resulting \`.symbols.json\` files (Swift Symbol Graph format)
- Filter by query/kind before returning
- Cache extracted symbol graphs per (module, platform) for the session duration
- Fits in \`Sources/Tools/Discovery/\` category

## Use Cases

1. \"Does SwiftUI have a \`ScrollPosition\` type?\" → query module=SwiftUI, query=ScrollPosition
2. \"What skip mechanisms does Swift Testing provide?\" → query module=Testing, query=skip
3. \"What's the signature of \`withKnownIssue\`?\" → query module=Testing, query=withKnownIssue, kind=func
4. Checking availability of new APIs across OS versions
