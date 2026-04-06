---
# cij-zj1
title: Add notarization tools (notarytool, stapler)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:29Z
updated_at: 2026-04-06T23:32:04Z
sync:
    github:
        issue_number: "263"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap macOS notarization CLI tools for app distribution workflows.

## Tools

- [x] `notarize_submit` — submit app/dmg/pkg for notarization (`xcrun notarytool submit ... --wait`)
- [x] `notarize_status` — check submission status (`xcrun notarytool info <id>`)
- [x] `notarize_log` — retrieve notarization log for diagnosing rejections (`xcrun notarytool log <id>`)
- [x] `staple` — attach notarization ticket to binary (`xcrun stapler staple`)

## Notes

- Requires Apple ID credentials or App Store Connect API key
- Credentials should be passed via tool parameters or keychain profile (`--keychain-profile`)
- `--wait` flag polls until notarization completes (can take minutes)
- Full workflow: archive → export → notarize → staple → distribute
- Consider timeout handling for long notarization waits

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog.


## Summary of Changes

Added `notarize` tool wrapping `xcrun notarytool` and `xcrun stapler`. Single tool with action parameter supporting submit (with --wait), status, log, staple, and history. Uses keychain profiles for auth. Registered in Build server and monolithic server.
