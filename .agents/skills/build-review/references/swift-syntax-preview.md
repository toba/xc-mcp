# Using swift-syntax for #Preview Extraction

## Current Approach

PreviewExtractor.swift uses a brace-balanced parser to find and strip `#Preview` blocks.

## Alternative: swift-syntax AST

`#Preview` is a freestanding macro → `MacroExpansionDeclSyntax` in the syntax tree.

```swift
import SwiftParser, SwiftSyntax

class PreviewVisitor: SyntaxVisitor {
    var previews: [(name: String?, body: String)] = []

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.macroName.text == "Preview" else { return .visitChildren }
        let name = node.arguments.first.flatMap { arg in
            arg.expression.as(StringLiteralExprSyntax.self)?.segments
                .compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
        }
        previews.append((name: name, body: node.trailingClosure?.statements.description))
        return .skipChildren
    }
}
```

For stripping: `SyntaxRewriter` subclass removing `MacroExpansionDeclSyntax` where
`macroName == "Preview"`.

**Trade-offs**: Better AST awareness and edge-case handling, but adds large swift-syntax
dependency (must match toolchain version). Current parser works well enough.

## IndexStoreDB

[indexstore-db](https://github.com/swiftlang/indexstore-db) provides programmatic access to
the build index for project-wide `#Preview` discovery and symbol resolution.

## Sources

- [swift-syntax](https://github.com/swiftlang/swift-syntax)
- [indexstore-db](https://github.com/swiftlang/indexstore-db)
