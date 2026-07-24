---
# 0q9-f2p
title: Investigate headless build/ship tooling from scottwillsey.com article
status: ready
type: task
priority: normal
created_at: 2026-07-22T06:22:11Z
updated_at: 2026-07-22T06:22:11Z
sync:
    github:
        issue_number: "431"
        synced_at: "2026-07-24T04:01:37Z"
---

Investigate tooling from the article "Building and shipping Mac and iOS apps without ever opening Xcode" (https://scottwillsey.com/building-and-shipping-mac-and-ios-apps-without-ever-opening-xcode/) for capabilities worth adding to xc-mcp.

The article's end-to-end headless pipeline is: xcodegen → xcodebuild archive → export → notarytool → stapler → codesign/spctl verify → devicectl install.

## Already covered by xc-mcp
- `xcodebuild` archive/export — `archive`, `export_archive`
- `xcrun notarytool` — `notarize`
- `xcrun devicectl` install — Device tools
- `codesign` inspection — Core/AppBundle codesign helper
- `swift test` — `swift_package_test`

## Candidate gaps worth investigating
- [ ] **xcodegen** — generate `.xcodeproj` from a YAML spec (reproducible, no binary project in git). We manipulate projects via XcodeProj and have scaffold tools, but a declarative generate-from-spec workflow may be a distinct capability worth exposing.
- [ ] **xcrun stapler staple** — attach the notarization ticket to the app bundle. Confirm whether `notarize` already staples; if not, add a stapling step/tool.
- [ ] **spctl -a -vvv -t exec** — Gatekeeper acceptance check ("would Gatekeeper accept this app?"). Not currently exposed; a useful post-notarization verification tool.
- [ ] **notarytool --keychain-profile** — document/support the keychain-profile credential flow vs. current auth approach.
- [ ] **Local.xcconfig pattern** — team ID / bundle prefix signing config kept out of VCS. Consider a session-defaults or scaffold convention for this.
- [ ] **release.sh orchestration** — single-command archive→export→notarize→staple→verify→install chain. Evaluate whether a composite "ship" workflow tool adds value over invoking steps individually.

## Deliverable
For each candidate, decide: already covered / add tool / not worth it. Spin off follow-up issues for anything greenlit.
