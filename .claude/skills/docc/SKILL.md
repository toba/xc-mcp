---
name: docc
description: |
  Write and maintain DocC documentation for Swift modules. Use when:
  (1) Creating new Documentation.docc catalogs
  (2) Writing or editing Main.md landing pages
  (3) Adding articles or guides to documentation
  (4) Documenting symbols with triple-slash comments
  (5) Organizing Topics sections
  (6) Adding images, diagrams, or code examples to docs
  (7) Fixing DocC build warnings or broken links
  (8) User mentions "documentation", "docc", "docs", or asks to document code
---

# DocC Documentation

Write documentation that builds correctly and follows Apple's DocC conventions.

## Quick Reference

### Documentation Comment Syntax

```swift
/// Summary sentence (becomes the abstract).
///
/// Discussion paragraph with additional context.
/// Can span multiple lines.
///
/// - Parameters:
///   - name: Description of the parameter.
///   - value: Another parameter description.
/// - Returns: What the function returns.
/// - Throws: ``ErrorType`` when something fails.
///
/// ## Example
/// ```swift
/// let result = myFunction(name: "test", value: 42)
/// ```
func myFunction(name: String, value: Int) throws -> String
```

### Symbol Linking

| Syntax | Use |
|--------|-----|
| `` ``TypeName`` `` | Link to type |
| `` ``TypeName/method`` `` | Link to member |
| `<doc:ArticleName>` | Link to article |

### Documentation Catalog Structure

```
ModuleName/
├── Sources/
│   └── *.swift
└── Documentation.docc/
    ├── Main.md           # Landing page (# ``ModuleName``)
    ├── Article.md        # Conceptual articles
    └── Resources/
        ├── image@2x.png      # Light mode
        └── image~dark@2x.png # Dark mode
```

### Main.md Template

```markdown
# ``ModuleName``

One-sentence summary of the module.

## Overview

Paragraph explaining the module's purpose and key concepts.

## Topics

### Group Name
- ``TypeName``
- ``TypeName/property``
- <doc:ArticleName>
```

### Article Template

```markdown
# Article Title

Summary sentence for the article.

## Overview

Introductory paragraph.

## Section Header

Content with code examples:

```swift
// Example code
```

![Image alt text](image-name)
```

## Layout Directives

For rich layouts beyond standard Markdown:

```markdown
@Row {
    @Column {
        Paragraph text explaining a concept.
    }

    @Column {
        ![Description](image-name)
    }
}

@TabNavigator {
    @Tab("First") {
        Content for first tab.
    }

    @Tab("Second") {
        Content for second tab.
    }
}
```

## Common Issues

| Problem | Solution |
|---------|----------|
| Symbol not found | Verify symbol is `public`; use full path ``Module/Type/member`` |
| Image not showing | Check file is in Documentation.docc, correct naming (`@2x`, `~dark`) |
| Article not linked | Add `<doc:ArticleName>` to Topics section in Main.md |
| Build warning "No overview" | Add `## Overview` section after title |

## Validation

Build documentation to check for errors:

```bash
# In Xcode: Product → Build Documentation
# Or via command line:
xcodebuild docbuild -scheme SchemeName
```
