---
name: upstream
description: |
  Check upstream repos for new changes that may be worth incorporating. Use when:
  (1) User says /upstream
  (2) User asks to "check upstream" or "what changed upstream"
  (3) User wants to know if upstream repos have new commits
  (4) User asks about syncing with or pulling from upstream sources
---

# Upstream Change Tracker

Check upstream repos for new commits, classify changes by relevance, and present a summary.

## Upstream Repos

| Repo | Default Branch | Relationship | Derived Into / Used By |
|------|---------------|-------------|----------------------|
| `giginet/xcodeproj-mcp-server` | `main` | Derived code | `Sources/Tools/Project/` (23 tools), `Sources/Utilities/PathUtility.swift` |
| `ldomaradzki/xcsift` | `master` | Derived code | `Sources/Core/BuildOutputParser.swift`, `BuildOutputModels.swift`, `CoverageParser.swift` |
| `Ryu0118/xcstrings-crud` | `main` | Derived code | `Sources/Core/XCStrings/` (7 files) |
| `tuist/xcodeproj` | `main` | Dependency (pinned from: 9.7.2) | All project manipulation tools via XcodeProj library |

## Workflow

### Step 1: Read Marker File

Read `.claude/skills/upstream/references/last-checked.json`.

- **If the file does not exist** → this is a first run. Set `FIRST_RUN=true`.
- **If the file exists** → parse the JSON to get `last_checked_sha` and `last_checked_date` per repo.

### Step 2: Fetch Changes (All 4 Repos in Parallel)

Run all four `gh api` calls in parallel using the Bash tool.

#### First Run (no marker file)

Fetch the last 30 commits per repo:

```bash
gh api "repos/giginet/xcodeproj-mcp-server/commits?per_page=30&sha=main" --jq '[.[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}]'
```

```bash
gh api "repos/ldomaradzki/xcsift/commits?per_page=30&sha=master" --jq '[.[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}]'
```

```bash
gh api "repos/Ryu0118/xcstrings-crud/commits?per_page=30&sha=main" --jq '[.[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}]'
```

```bash
gh api "repos/tuist/xcodeproj/commits?per_page=30&sha=main" --jq '[.[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}]'
```

Also fetch the changed files for each repo's recent commits to classify relevance:

```bash
gh api "repos/giginet/xcodeproj-mcp-server/commits?per_page=30&sha=main" --jq '[.[].sha]' | jq -r '.[]' | head -30 | while read sha; do gh api "repos/giginet/xcodeproj-mcp-server/commits/$sha" --jq '{sha: .sha, files: [.files[].filename]}'; done
```

(Repeat for other repos with appropriate branch names.)

#### Subsequent Runs (marker file exists)

Use the compare API:

```bash
gh api "repos/giginet/xcodeproj-mcp-server/compare/{LAST_SHA}...main" --jq '{total_commits: .total_commits, commits: [.commits[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}], files: [.files[].filename]}'
```

```bash
gh api "repos/ldomaradzki/xcsift/compare/{LAST_SHA}...master" --jq '{total_commits: .total_commits, commits: [.commits[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}], files: [.files[].filename]}'
```

```bash
gh api "repos/Ryu0118/xcstrings-crud/compare/{LAST_SHA}...main" --jq '{total_commits: .total_commits, commits: [.commits[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}], files: [.files[].filename]}'
```

```bash
gh api "repos/tuist/xcodeproj/compare/{LAST_SHA}...main" --jq '{total_commits: .total_commits, commits: [.commits[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}], files: [.files[].filename]}'
```

**Fallback:** If the compare API returns 404 (e.g. force-push rewrote history), fall back to date-based query:

```bash
gh api "repos/{owner}/{repo}/commits?since={LAST_DATE}&sha={BRANCH}&per_page=100" --jq '[.[] | {sha: .sha, date: .commit.committer.date, message: (.commit.message | split("\n") | .[0]), author: .commit.author.name}]'
```

### Step 3: Classify Changed Files by Relevance

Use these mappings to assign HIGH / MEDIUM / LOW relevance to each changed file:

#### giginet/xcodeproj-mcp-server

| Relevance | Path Patterns |
|-----------|--------------|
| **HIGH** | `Sources/XcodeProjectMCP/*.swift` |
| **MEDIUM** | `Package.swift`, `Tests/**` |
| **LOW** | `.github/**`, `Dockerfile`, `README.md`, `Documentation/**` |

#### ldomaradzki/xcsift

| Relevance | Path Patterns |
|-----------|--------------|
| **HIGH** | `Sources/OutputParser.swift`, `Sources/Models.swift`, `Sources/CoverageParser.swift` |
| **MEDIUM** | `Sources/Configuration.swift`, `Package.swift`, `Tests/**` |
| **LOW** | `Sources/Install/**`, `Sources/main.swift`, `.github/**`, `plugins/**`, `README.md`, `docs/**` |

#### Ryu0118/xcstrings-crud

| Relevance | Path Patterns |
|-----------|--------------|
| **HIGH** | `Sources/XCStringsKit/**` |
| **MEDIUM** | `Sources/XCStringsMCP/**`, `Sources/XCStringsCLI/**`, `Tests/**` |
| **LOW** | `.github/**`, `README.md` |

#### tuist/xcodeproj (dependency watch)

This is a library dependency, not derived code. Focus on API changes, bug fixes, and breaking changes.

| Relevance | Path Patterns |
|-----------|--------------|
| **HIGH** | `Sources/XcodeProj/Objects/**` (PBX model types we use directly), `Sources/XcodeProj/Scheme/**`, `Sources/XcodeProj/Project/**` |
| **MEDIUM** | `Sources/XcodeProj/Utils/**`, `Sources/XcodeProj/Extensions/**`, `Package.swift`, `CHANGELOG.md`, `Tests/**` |
| **LOW** | `.github/**`, `README.md`, `Documentation/**`, `fixtures/**`, `Makefile` |

Also note any tags/releases since last check — version bumps may warrant updating `Package.swift`.

Files not matching any pattern → **MEDIUM** (unknown = worth reviewing).

### Step 4: Present Summary

Format the output as follows:

```
# Upstream Changes

## giginet/xcodeproj-mcp-server (N new commits since YYYY-MM-DD)

### Commits
- `abc1234` Fix target dependency resolution — @author (2025-05-01)
- `def5678` Add support for build rules — @author (2025-04-28)

### Changed Files

**HIGH relevance** (directly mapped into our tools):
- Sources/XcodeProjectMCP/AddFileTool.swift
- Sources/XcodeProjectMCP/BuildSettingsTool.swift

**MEDIUM relevance** (may affect behavior):
- Package.swift

**LOW relevance** (infrastructure/docs):
- README.md

**Assessment:** 2 high-relevance changes to tool implementations — worth reviewing for potential incorporation.

---

(repeat for each repo)

---

## Overall Recommendation
(Summarize: how many repos have high-relevance changes, suggest priority order for review)
```

If a repo has **no new commits**, show:

```
## repo/name — No new commits since last check (YYYY-MM-DD)
```

### Step 5: Update Marker File

Build the new marker JSON with the HEAD SHA and current date for each repo.

- **First run:** Write the marker file automatically (tell the user it was created).
- **Subsequent runs:** Ask the user "Update the last-checked markers to current HEAD?" before writing.

Write to `.claude/skills/upstream/references/last-checked.json`:

```json
{
  "giginet/xcodeproj-mcp-server": {
    "last_checked_sha": "<HEAD_SHA>",
    "last_checked_date": "<ISO_DATE>"
  },
  "ldomaradzki/xcsift": {
    "last_checked_sha": "<HEAD_SHA>",
    "last_checked_date": "<ISO_DATE>"
  },
  "Ryu0118/xcstrings-crud": {
    "last_checked_sha": "<HEAD_SHA>",
    "last_checked_date": "<ISO_DATE>"
  },
  "tuist/xcodeproj": {
    "last_checked_sha": "<HEAD_SHA>",
    "last_checked_date": "<ISO_DATE>"
  }
}
```

The `references/` directory should be created if it doesn't exist:

```bash
mkdir -p .claude/skills/upstream/references
```
