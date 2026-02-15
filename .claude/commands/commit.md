---
description: Stage all changes and commit with a descriptive message
---

## Active Codebase Expectations

This is an active codebase with multiple agents and people making changes concurrently. Do NOT waste time investigating unexpected git status:
- If a file you edited shows no changes, someone else likely already committed it - move on
- If files you didn't touch appear modified, another agent may have changed them - include or exclude as appropriate
- Focus on what IS changed, not what ISN'T

## Step 1: Run Critical Review (Parallel)

**IMPORTANT**: Before committing, run lint and tests **in parallel** (single message, multiple Bash calls).

Execute these commands concurrently:
1. `swiftlint` - check for lint violations
2. `swift build` - verify compilation
3. `swift test` - run test suite

Then review the diff for security/quality issues.

If any command fails or review finds blocking issues, report them and STOP. Do not proceed to commit.

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

### Step 4: Update Homebrew Tap

After pushing the tag:

1. Wait for the release workflow to complete:
   ```bash
   gh run watch $(gh run list --repo toba/xc-mcp --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId') --repo toba/xc-mcp
   ```

2. Fetch the sha256 from the release:
   ```bash
   gh release download v<new-version> --repo toba/xc-mcp --pattern "*.sha256" -O - | awk '{print $1}'
   ```

3. Update `../homebrew-xc-mcp/Formula/xc-mcp.rb`:
   - Change the `url` line to use the new version tag
   - Change the `version` line to the new version (without 'v' prefix)
   - Set `sha256` to the value from step 2

4. Commit and push the homebrew tap:
   ```bash
   cd ../homebrew-xc-mcp
   git add Formula/xc-mcp.rb
   git commit -m "bump to v<new-version>"
   git push
   cd ../xc-mcp
   ```

### Version Examples

- Current: v1.2.3
  - Bug fix → v1.2.4 (patch)
  - New --no-sandbox flag → v1.3.0 (minor)
  - Changed tool argument names → v2.0.0 (major)
