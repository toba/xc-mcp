---
# gl6-64d
title: build_device fails to find connected device by UDID
status: in-progress
type: bug
priority: normal
created_at: 2026-03-14T01:10:38Z
updated_at: 2026-03-14T01:13:41Z
sync:
    github:
        issue_number: "212"
        synced_at: "2026-03-14T01:24:34Z"
---

## Description

\`build_device\` fails with \`Unable to find a device matching the provided destination specifier\` when given a valid device UDID from \`list_devices\`.

\`list_devices\` correctly finds the device:

```
📱 Jason's iPad
   UDID: A5CC2917-0B66-5306-8C9F-A60BFEB112C1
   Type: iPad mini (6th generation)
   OS Version: 18.7.3
   Connection: wired
```

\`devicectl list devices\` also confirms it:

```
Jason's iPad   Jasons-iPad.coredevice.local   A5CC2917-0B66-5306-8C9F-A60BFEB112C1   available (paired)   iPad mini (6th generation) (iPad14,1)
```

But \`build_device\` passes the UDID to \`xcodebuild -destination "platform=iOS,id=<UDID>"\` and xcodebuild cannot find it. The device does not appear in xcodebuild's destination list (only simulators are listed).

## Likely Cause

The UDID format from \`devicectl\` (CoreDevice framework) may differ from what \`xcodebuild\` expects. Older devices use a 40-char hex UDID, while CoreDevice uses a UUID format. xcodebuild may need \`platform=iOS,id=<UDID>\` with the device's actual hardware UDID, or the device may need to be trusted/provisioned first.

## Steps to Reproduce

1. Connect an iPad mini (6th generation) via USB
2. Confirm it appears in \`list_devices\`
3. Call \`build_device\` with the returned UDID
4. Build fails with destination not found

## Expected Behavior

\`build_device\` should successfully build for the connected device.



## Additional Findings

The CoreDevice UDID (`A5CC2917-0B66-5306-8C9F-A60BFEB112C1`) is valid and works with `devicectl` commands:

- `xcrun devicectl device install app --device <UDID>` — works
- `xcrun devicectl device process launch --device <UDID>` — works

The issue is specifically that `xcodebuild -destination "platform=iOS,id=<UDID>"` does not recognize the device. The device does not appear in xcodebuild's destination list at all (only simulators are listed), even though it is connected, paired, and available.

## Workaround

Build with `-destination "generic/platform=iOS"`, then install and launch via `devicectl`:

```bash
xcodebuild -project Foo.xcodeproj -scheme Foo -destination "generic/platform=iOS" build
xcrun devicectl device install app --device <UDID> /path/to/Foo.app
xcrun devicectl device process launch --device <UDID> com.example.foo
```

This successfully builds, installs, and launches on the device.
