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

## Step 3: Push (if requested)

If $ARGUMENTS contains "push" or user requested push, run `git push`.
