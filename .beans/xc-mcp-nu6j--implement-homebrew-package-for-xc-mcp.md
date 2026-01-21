---
# xc-mcp-nu6j
title: Implement Homebrew package for xc-mcp
status: completed
type: feature
created_at: 2026-01-21T17:07:43Z
updated_at: 2026-01-21T17:07:43Z
---

Create a custom Homebrew tap (toba/homebrew-xc-mcp) to enable installation via brew tap toba/xc-mcp && brew install xc-mcp.

## Checklist
- [x] Create git tag v0.1.0 for first release
- [x] Create homebrew-xc-mcp tap repository structure
- [x] Create Formula/xc-mcp.rb with build instructions
- [x] Push tag and compute SHA256 hash (sha256: 52c1616791eed2389fd3391f277f0e85afc27b50aa416f363d5ddf15a9e31f47)
- [x] Update README.md with Homebrew installation instructions
- [x] Create tap repository README.md
- [x] Create GitHub repo toba/homebrew-xc-mcp and push tap files

## Files Created

- https://github.com/toba/homebrew-xc-mcp
  - `Formula/xc-mcp.rb` - Homebrew formula
  - `README.md` - Tap documentation