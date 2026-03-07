---
# orp-ndc
title: 'add_to_copy_files_phase: support build file attributes'
status: completed
type: bug
priority: high
created_at: 2026-03-07T18:55:41Z
updated_at: 2026-03-07T19:06:36Z
parent: xav-ojz
sync:
    github:
        issue_number: "175"
        synced_at: "2026-03-07T19:13:27Z"
---

Embedding a framework via the "Embed Frameworks" copy phase doesn't set CodeSignOnCopy or RemoveHeadersOnCopy on the PBXBuildFile entry. Required Python patching.

## Fix
Add \`attributes\` parameter (array of strings) to \`add_to_copy_files_phase\`. Default to ["CodeSignOnCopy", "RemoveHeadersOnCopy"] when the phase is "Embed Frameworks".

## Tasks
- [ ] Add \`attributes\` optional parameter to tool schema
- [ ] Apply attributes to PBXBuildFile settings dict
- [ ] Auto-default attributes when phase name contains "Embed Frameworks"
- [ ] Add test: attributes applied when specified
- [ ] Add test: auto-default for Embed Frameworks phase


## Summary of Changes
Added attributes parameter to add_to_copy_files_phase. Auto-defaults to [CodeSignOnCopy, RemoveHeadersOnCopy] for Embed Frameworks phases. Uses PBXBuildFile settings ATTRIBUTES key.
