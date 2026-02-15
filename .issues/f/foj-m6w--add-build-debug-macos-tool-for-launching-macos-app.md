---
# foj-m6w
title: Add build_debug_macos tool for launching macOS apps under LLDB
status: completed
type: feature
created_at: 2026-02-15T20:35:46Z
updated_at: 2026-02-15T20:35:46Z
---

Implemented build_debug_macos tool that builds incrementally and launches macOS apps under LLDB debugger with proper DYLD_FRAMEWORK_PATH/DYLD_LIBRARY_PATH environment. Changes: LLDBSession.launch(), LLDBSessionManager.createLaunchSession(), LLDBRunner.launchProcess(), new BuildDebugMacOSTool, registered in both XcodeMCPServer and DebugMCPServer.
