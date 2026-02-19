---
description: Stage all changes and commit with a descriptive message
---

## Active Codebase Expectations

This is an active codebase with multiple agents and people making changes concurrently. Do NOT waste time investigating unexpected git status:
- If a file you edited shows no changes, someone else likely already committed it - move on
- If files you didn't touch appear modified, another agent may have changed them - include or exclude as appropriate
- Focus on what IS changed, not what ISN'T

## Step 1: Review Changes

Review the diff for security/quality issues. If you find blocking issues, report them and STOP.

**Do NOT run swift format, swiftlint, swift build, or swift test** — the pre-commit hook handles all of these automatically. Running them here wastes time since they'll run again during `git commit`.

## Step 2: Stage and Commit

1. Run `git add -A` to stage all changes
2. Run `git diff --cached --stat` to review what will be committed
3. Commit ALL staged changes - never unstage or filter files
4. Create a commit with a concise, descriptive message:
   - Lowercase, imperative mood (e.g., "add feature" not "Added feature")
   - Focus on "why" not just "what"
   - Include affected bean IDs if applicable
5. Run `git status` to confirm the commit succeeded
6. Run `todo sync` to sync issues to GitHub

## Step 3: Push and Version (if requested)

If $ARGUMENTS contains "push" or user requested push:

1. Get the latest version tag: `git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1`
2. Get the previous tag's commit to see what changed: `git log <latest-tag>..HEAD --oneline`
3. Determine version increment based on changes since last tag:
   - **patch** (x.y.Z): Bug fixes, minor improvements, documentation
   - **minor** (x.Y.0): New features, new tools, new flags (like --no-sandbox)
   - **major** (X.0.0): Breaking changes, API changes, removed functionality
4. Ask user to confirm the version increment (show current version and proposed new version)
5. After confirmation:
   ```bash
   git push
   git tag v<new-version>
   git push origin v<new-version>
   ```
6. The GitHub Actions workflow will automatically create a release with binaries

### Version Examples

- Current: v1.2.3
  - Bug fix → v1.2.4 (patch)
  - New --no-sandbox flag → v1.3.0 (minor)
  - Changed tool argument names → v2.0.0 (major)
