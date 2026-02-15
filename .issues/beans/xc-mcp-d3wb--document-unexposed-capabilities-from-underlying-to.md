---
# xc-mcp-d3wb
title: Document unexposed capabilities from underlying tools
status: completed
type: task
priority: normal
created_at: 2026-01-21T07:35:21Z
updated_at: 2026-01-21T07:35:21Z
sync:
    github:
        issue_number: "15"
        synced_at: "2026-02-15T22:08:23Z"
---

Research findings on capabilities available in xcodebuild, simctl, devicectl, and lldb that are not currently exposed through xc-mcp MCP tools.

## xcodebuild - Missing Capabilities

### Archive & Distribution
- **Archive builds** (`archive` action, `-archivePath`) - Create distributable archives
- **Export archives** (`-exportArchive`, `-exportOptionsPlist`) - Export for App Store, ad-hoc, enterprise
- **Notarization** (`-exportNotarizedApp`) - Notarize during export

### Static Analysis & Quality
- **Static analysis** (`analyze` action) - Find bugs without running code
- **Code coverage** (`-enableCodeCoverage`) - Collect test coverage data
- **Sanitizers** - Address sanitizer, thread sanitizer, undefined behavior sanitizer

### Advanced Testing
- **Test-without-building** - Run pre-compiled test bundles (xctestrun files)
- **Build-for-testing** - Generate xctestrun without executing tests
- **Granular test selection** (`-only-testing`, `-skip-testing`) - Run specific test classes/methods
- **Parallel test workers** (`-parallel-testing-worker-count`) - Configure concurrent test execution
- **Test timeout** (`-executionTimeAllowance`) - Per-test timeout with spindump on hang
- **Result bundles** (`-resultBundlePath`) - Generate .xcresult with full diagnostics

### Discovery
- **Show SDKs** (`-showsdks`) - List all available SDKs with versions
- **Show run destinations** (`-showRunDestinations`) - Available destinations for testing

### Localization
- **XLIFF export/import** - Extract and reimport translations

---

## simctl - Missing Capabilities

### Push Notifications
- **Push notification simulation** (`push`) - Test push without APNs

### Privacy & Permissions
- **Privacy settings** (`privacy grant/revoke/reset`) - Control app permissions programmatically
  - Camera, microphone, photos, contacts, location, calendars, reminders, siri, motion, media-library

### Device Management
- **Create simulators** (`create`) - Create new simulators with custom names/runtimes
- **Clone simulators** (`clone`) - Duplicate existing simulators
- **Delete simulators** (`delete`) - Remove simulators from disk
- **Upgrade simulators** (`upgrade`) - Upgrade to newer runtime

### Watch-Phone Pairing
- **Pair/unpair** (`pair`, `unpair`) - Manage watchOS-iOS simulator pairs

### Clipboard
- **pbcopy** - Send Mac clipboard to simulator
- **pbpaste** - Get simulator clipboard content

### Media
- **Add media** (`addmedia`) - Add photos, videos, live photos, contacts to simulator

### Preferences
- **Read/write preferences** - Change locale, language, and other settings

---

## devicectl - Missing Capabilities

### Process Management
- **List processes** (`device info processes`) - Get running processes with PIDs
- **List apps** (`device info apps`) - Enumerate installed applications
- **Pause/resume process** (`device process pause/resume`) - Suspend execution
- **Interrupt process** (`device process interrupt`) - Send interrupt signal

### Launch Options
- **Console streaming** (`--console` flag) - Stream app logs during launch
- **Start-stopped launch** (`--start-stopped`) - Launch suspended for debugger attachment

### Debugging Infrastructure
- **Notification observe** - Establish secure tunnel for remote debugging

---

## lldb - Missing Capabilities

### Stepping Controls
- **Step into** (`thread step-in` / `s`) - Step into function calls
- **Step over** (`thread step-over` / `n`) - Step over function calls
- **Step out** (`thread step-out` / `f`) - Step out of current function
- **Step instruction** (`thread step-inst` / `si`) - Single instruction step

### Watchpoints
- **Set watchpoint** (`watch set var`) - Break on variable write
- **Watchpoint management** - Enable, disable, delete, list watchpoints

### Memory Access
- **Read memory** (`memory read` / `x`) - Read memory at address
- **Write memory** (`memory write`) - Modify memory
- **Memory region info** (`memory region`) - Query memory layout

### Register Access
- **Read/write registers** - Inspect and modify CPU registers

### Expression Evaluation
- **Execute expressions** (`expression` / `e`) - Evaluate code in current context
- **Print object descriptions** (`po`) - Get detailed object info

### Python Scripting
- **Automated breakpoint scripts** - Run Python on breakpoint hit
- **Custom LLDB commands** - Extend debugger with domain-specific tools
- **Data structure traversal** - Programmatic inspection of complex objects

---

## Entirely Missing Domains

### Code Signing & Provisioning
- Certificate management
- Provisioning profile handling
- Entitlements management

### Crash & Diagnostics
- Crash log retrieval and analysis
- Symbolication
- .xcresult bundle parsing with xcresulttool

### Performance Profiling
- Instruments integration
- Memory profiling
- CPU profiling
- Energy diagnostics

### Network
- Network link conditioner simulation
- Traffic inspection

### Accessibility
- Accessibility inspector integration
- VoiceOver testing

### Data Inspection
- Core Data debugging
- UserDefaults inspection
- Keychain access (for debugging)

---

## Priority Tiers

### Tier 1 - High Value, Low Effort
1. Push notification simulation
2. Code coverage collection
3. Show SDKs command
4. Privacy/permissions management
5. Granular test selection

### Tier 2 - High Value, Medium Effort
1. Archive and export builds
2. Result bundle generation and analysis
3. Expression evaluation in debugger
4. LLDB stepping controls
5. Device process listing

### Tier 3 - Medium Value, Higher Effort
1. Static analysis
2. Watchpoints
3. Memory inspection
4. Simulator creation/cloning/deletion
5. Python scripting integration for LLDB
