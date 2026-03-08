---
# fwb-ilh
title: 'xc-project: scaffold_module should handle public imports and access control'
status: ready
type: feature
priority: normal
created_at: 2026-03-08T17:51:27Z
updated_at: 2026-03-08T17:51:27Z
parent: xav-ojz
sync:
    github:
        issue_number: "196"
        synced_at: "2026-03-08T17:51:36Z"
---

## Problem

When extracting a Swift module from an app target into a framework, the most tedious and error-prone work is:

1. Determining which types need \`public\` access control
2. Determining which imports need \`public import\` vs \`import\`
3. Creating protocol abstractions for generic types that can't cross module boundaries

Currently \`add_target\` creates the target structure but the agent must iterate through 3-5 build cycles fixing access control and import visibility errors by hand.

## Proposed Enhancement

The existing \`scaffold_module\` / \`add_target\` composite tool (xav-ojz) could include guidance or automation for:

- **Public import detection**: When a framework's public API references types from another module, that module needs \`public import\`. A post-scaffold checklist or validation step could flag this.
- **Access control template**: New framework files could include a comment or template noting that types used by the app target need \`public\`.

## Context

During a module extraction, the following pattern repeated across every file:
- \`struct Foo: Action {}\` → needs \`public struct\`, \`public init\`
- \`import Core\` → needs \`public import Core\` when Foo's public API uses Core types
- \`import Foundation\` → needs \`public import Foundation\` when NSRange appears in public signatures
- Protocol conformances on public types require the protocol's module to be publicly imported

This is mechanical work that could be partially automated or at least documented in scaffold output.
