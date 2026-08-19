# NDM2 — Native Desktop UI Migration Report

**Date:** 19 August 2026  
**Scope:** Initial native UI migration foundation in `Alaa91H/NDM2`.

## Executive Summary

NDM2 now contains an independently buildable **C++20 / Qt 6 / Qt Quick / QML** desktop application in `native/`. The work preserves the original NOVA repository history and keeps the Rust daemon, download engine and all browser/installer components in place. The new application reads and mutates real NOVA daemon state only through a dedicated C++ adapter; QML contains no HTTP calls, token logic or simulated task data.

> This is an initial native migration increment, not a claim of complete UI-parity. The table and task actions are real-core integrations by contract, while several advanced pages remain deliberately identified as follow-up work rather than replaced with mock UI.

## 1. What Changed

| Area | Change |
|---|---|
| Project layout | Added a root CMake project and the independent `native/` Qt application subtree. |
| Native application | Added a C++20 executable named `NDM2`, with Qt Core, Gui, Network, Quick, Quick Controls 2 and Widgets. |
| Core adapter | Added `CoreAdapter`, the sole client for the daemon’s authenticated loopback HTTP contract. |
| Data model | Added a role-based `QAbstractListModel` mapping true task status, bytes, speed, ETA, paths, segments, retries and errors. |
| Primary UI | Added native QML main navigation, filterable download table, live state indicator, selection toolbar, progress display and empty/error states. |
| Task workflows | Added native dialogs/actions for add, pause, resume, cancel, retry, delete, safe open/reveal and core bandwidth submission. |
| Inspection | Added a download details drawer with live model-derived information and a speed-history graph based on sampled actual speed values. |
| Desktop integration | Added native folder selection, file/folder shell actions, keyboard shortcuts, system tray menu and persisted window geometry. |
| Presentation | Added dark/light/system presentation choice, density setting and Qt `LayoutMirroring` for Arabic, Hebrew, Persian and Urdu layout direction. |
| Documentation | Added a pre-coding audit, architecture/build guide and this migration report. |

## 2. Core Components Intentionally Left Untouched

No files inside `src-tauri/` were edited. The original Tauri host and Rust daemon remain available in NDM2 intact, as do the existing libcurl multi engine, segmented transfer implementation, scheduling, retry/queue/bandwidth systems, profiles, rules, mirrors/failover, checksums, metadata cache, telemetry, yt-dlp/FFmpeg tools, browser extension, native messaging, token/authentication model, SSRF protection, installer infrastructure and engine-capability logic.

A repository diff check of `src-tauri/` completed successfully before the test run. The Rust core tests then completed with **712 passed, 0 failed**.

## 3. New Qt Architecture

| Layer | Primary files | Responsibility |
|---|---|---|
| Native presentation | `native/qml/` | Visual layout, navigation, dialogs and display-only interactions. |
| App services | `native/src/services/` | Task selection/actions, speed sampling and persisted presentation preferences. |
| Models | `native/src/models/DownloadModel.*` | High-performance Qt model roles for a large changing task collection. |
| Core adapter | `native/src/adapter/CoreAdapter.*` | Authenticated daemon communications, loopback validation, responses and capability retrieval. |
| Desktop platform | `native/src/platform/DesktopService.*`, `main.cpp` | File chooser/shell operations, tray and local window preferences. |

The design keeps QML declarative. It does not spread daemon routes, bearer-token handling, network replies or JSON parsing through visual components.

## 4. Core/UI Communication Mechanism

NDM2 takes the daemon URL from `NOVA_DAEMON_URL` or `--daemon-endpoint`, and the bearer token from `NOVA_DAEMON_TOKEN` or `--daemon-token`. `CoreAdapter` accepts **only** `localhost`, `127.0.0.1` and `::1`, retains the original bearer-authentication boundary, and writes `Authorization: Bearer <token>` only in C++ network requests.

| Capability | Existing daemon contract consumed by the adapter |
|---|---|
| Task collection | `GET /api/downloads` |
| Create task | `POST /api/downloads` |
| Pause/resume | `POST /api/downloads/{id}/pause`, `POST /api/downloads/{id}/resume` |
| Retry | `POST /api/downloads/{id}/redownload` |
| Cancel/delete | `DELETE /api/downloads/{id}` |
| Queue priority | `POST /api/engine/queue` |
| Global bandwidth | `POST /api/engine/bandwidth` |
| Scheduler bridge | `POST /api/engine/scheduler/update` |
| Capability detection | `GET /api/engines/capabilities` |

The current adapter uses a 1.2-second coalesced authenticated refresh of the true `/api/downloads` payload. The next migration increment should add the existing SSE full/delta stream to avoid even this bounded refresh in high-scale libraries.

## 5. Features Migrated in This Increment

The main view has **All**, **Active**, **Queued**, **Completed**, **Failed**, **Scheduled**, **Categories** and **History** navigation. Its table is model-driven and displays filename, type, status, progress, downloaded/total size, speed, ETA, connections, category and errors. The visual design uses a native Qt Quick hierarchy with status colors, selection/focus states, responsive sizing and no web view, HTML, CSS, React, JavaScript host layer or fake task state.

The implemented native workflows are add download, refresh, pause, resume, cancel, retry, delete, selected-task details, open file, reveal folder, global bandwidth update, local presentation preferences and native tray access. The add dialog transfers only user-supplied fields to the daemon; controls that need a verified capability are not fabricated.

## 6. Tests Executed and Results

| Test or check | Command | Result |
|---|---|---|
| Debug Qt build | `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build -j2` | Passed. |
| Release Qt build | `cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-release -j2` | Passed. |
| QML startup smoke test | `timeout 5s env QT_QPA_PLATFORM=offscreen ./build/native/NDM2 --daemon-endpoint http://127.0.0.1:65530 --daemon-token smoke-test-token` | Passed; window/QML initialized and remained alive until expected timeout. |
| CMake test discovery | `ctest --test-dir build-release --output-on-failure` | Passed with no CTest targets registered. |
| Rust core regression suite | `cargo test --manifest-path src-tauri/Cargo.toml --lib` | Passed: **712 passed, 0 failed**. |
| Core preservation | `git diff --exit-code -- src-tauri` | Passed; no uncommitted source changes in the Rust Core. |
| QML static lint | `qmllint` on QML files | Parsed; reported non-blocking unqualified-access/style warnings for context properties. |

The smoke test deliberately targeted an unused **loopback** port. It verifies native UI loading and graceful unavailable-daemon behavior but does not claim a full real-daemon functional test. End-to-end testing requires a running NOVA daemon and its genuine authentication token; it should then cover real downloadable URLs, pause/resume, queue persistence, restart recovery, system tray behavior and all core-gated pages.

## 7. Remaining Limitations and Required Follow-up

| Priority | Work remaining | Rationale |
|---|---|---|
| High | Add direct `downloads`/`downloads-delta` SSE consumption to `CoreAdapter`. | Required for the most efficient high-frequency telemetry path already offered by the core. |
| High | Finish native queue editor with persistent drag-and-drop ordering and concurrent-limit controls. | The adapter has a queue-priority bridge but no full queue page yet. |
| High | Add capability-gated scheduler, profiles, rules, mirrors/failover, checksum and diagnostics pages. | These existing real core capabilities must have equivalent native UI access. |
| High | Add media probe/format workflow, external-tool controls and browser integration view. | Required to expose the existing yt-dlp/FFmpeg and browser-extension surface. |
| Medium | Add Qt translation catalogs and load them via `QTranslator`. | Layout mirroring is present, but full Arabic, Hebrew, Persian, English and German text catalogs are not yet migrated. |
| Medium | Add native notifications, richer keyboard navigation, accessibility audit and high-DPI/manual multi-monitor test matrix. | Required to finish desktop-polish acceptance criteria. |
| Medium | Eliminate QML lint unqualified-access warnings by replacing direct context-property access with registered typed QML singletons. | Improves static analysis and maintainability; it does not block the compiled application. |
| High | Run a real Core end-to-end test matrix. | Required before claiming complete functional parity or removing the legacy desktop frontend. |

## 8. Exact Build and Run Commands

```bash
# Debug build
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j2

# Release build
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j2
cmake --install build-release --prefix dist

# Run with a pre-existing NOVA daemon; do not put a sensitive token into source files
export NOVA_DAEMON_URL=http://127.0.0.1:3199
export NOVA_DAEMON_TOKEN='token-issued-by-the-existing-nova-host'
./build/native/NDM2

# Equivalent controlled-development invocation
./build/native/NDM2 \
  --daemon-endpoint http://127.0.0.1:3199 \
  --daemon-token "$NOVA_DAEMON_TOKEN"

# Run the preserved Rust core library test suite
cargo test --manifest-path src-tauri/Cargo.toml --lib
```

## Conclusion

NDM2 has a compiled native Qt desktop foundation that is separated from, and non-destructive to, NOVA’s existing Rust Core. The appropriate next step is a staged continuation of native feature migration against a running real daemon; the legacy React/Tauri frontend should remain intact until the follow-up high-priority functionality and real end-to-end parity tests are complete.
