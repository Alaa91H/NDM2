# NDM2 Phase 2 — Native Feature Migration Report

**Date:** 19 August 2026  
**Scope:** Continued migration of NOVA desktop capabilities into the independent C++20 / Qt 6 / Qt Quick application in `native/`.

## Executive Status

Phase 2 materially extends the native NDM2 application, while preserving the complete NOVA Rust Core and the legacy React/Tauri frontend. NDM2 now uses the existing authenticated loopback daemon interface for its central download model, event updates, task actions, queue data, bandwidth state, profiles, statistics and logs. The work includes a real-daemon test session—not mocked responses—covering an HTTPS transfer, live SSE updates, pause, resume, cancellation/deletion, retry dispatch, queue priority, bandwidth, metadata updates, profile switching, restart persistence and Arabic/English startup configurations.

> **NDM2 is not feature-complete and must not replace the legacy frontend yet.** Queue reordering, scheduler management, rules, mirrors, media, browser integration, notifications, comprehensive settings and complete translations remain migration work.

## 1. Features Implemented in this Increment

| Area | Native NDM2 implementation | Core-backed data/action | Real-daemon evidence | Status |
|---|---|---|---|---|
| Download model | `DownloadModel` now updates rows incrementally instead of resetting the list for every live event. | `GET /api/downloads`, `downloads`, `downloads-delta` SSE events. | The real 10 MiB transfer emitted recurring `downloads-delta` payloads with changing bytes, state and speed. | Implemented and exercised. |
| Real-time synchronization | `CoreAdapter` opens an authenticated SSE stream, parses complete/delta events, reconnects after stream completion, and retains a 10-second bounded reconciliation refresh. | `GET /api/downloads/events` and `GET /api/downloads`. | Native app launched against the real daemon while an actual transfer was active. | Implemented and smoke-tested. |
| Download list | Native model roles expose file name, source URL, status, bytes, speed, ETA, connections, category, queue, engine, segments, error and retry values. | Existing task JSON. | Core task payloads used directly; no mock list exists. | Implemented and exercised. |
| Basic actions | Add, pause, resume, cancel/delete, retry, delete files flag, open/reveal and update metadata wrapper. | Existing task routes. | Pause/resume, delete, retry dispatch and `PATCH` rename were exercised on genuine daemon tasks. | Implemented; action routes verified directly against the Core. |
| Add workflow | Polished native dialog submits only known request fields: URL, optional name, destination, category, connections, direct per-task speed limit and immediate-start choice. | `POST /api/downloads`; `directOptions.speedLimitKbs`. | A genuine HTTP(S) task was created through this Core request contract. | Implemented; contract verified. |
| Details | Native drawer has overview, progress/speed graph, source/file information and actual daemon log records. | Task model plus `GET /api/logs`. | Real task data was supplied by the daemon. | Partial: per-task filtered trace is still missing. |
| Queue | Native Queue page presents live daemon queue entries and summary, and supplies the confirmed queue-priority bridge. | `GET /api/engine/queue`, `POST /api/engine/queue`. | Priority change returned the real Core `High` response. | Partial: no reorder control is shown because no confirmed ordering route was found. |
| Bandwidth | Global bandwidth is read and set via native settings; task-specific add limit maps to supported direct options. | `GET/POST /api/engine/bandwidth`. | Global limit was set to 256 KB/s and read back from the daemon. | Implemented and exercised. |
| Profiles | Native settings expose the actual Core profile list and active-profile selection. | `GET/POST /api/engine/profiles`. | Changed to `economical`, observed it as active, then restored `balanced`. | Implemented and exercised. |
| Diagnostics | Native Diagnostics page shows real Core session statistics and daemon log entries. | `GET /api/stats`, `GET /api/logs`. | Read from live daemon. | Partial: log-level and task-trace controls remain missing. |
| System tray | Native tray includes visibility, active/paused queue summary, Core-backed pause-all/resume-all and exit. | Model-derived current Core state; existing per-task pause/resume routes. | Compiled and connected to live-state model; manual desktop-shell verification is still required. | Partial. |
| Themes and density | Persistent `dark`, `light`, `system`, `comfortable` and `compact` presentation choices. The system palette determines the system scheme. | Local `QSettings`; no Core setting invented. | English/dark and Arabic/light/compact native startup smoke tests passed. | Implemented; visual/manual audit pending. |
| RTL/LTR | `QGuiApplication::setLayoutDirection` is changed from stored language and QML inherits `LayoutMirroring`; no manual per-control mirroring was added. | Local language preference. | Arabic and English startup configurations passed. | Partial: translation catalogs and manual layout audit remain needed. |
| Loopback boundary | Adapter retains the existing local-only daemon restriction. | Adapter permits only `127.0.0.1`, `localhost`, `::1`. | NDM2 startup with a non-loopback endpoint was safely rejected by the adapter path without attempting a normal daemon connection. | Implemented and exercised. |

## 2. Qt Architecture After Phase 2

| Layer | Files | Responsibility |
|---|---|---|
| Presentation | `native/qml/Main.qml`, `native/qml/pages/`, `native/qml/dialogs/`, `native/qml/components/` | Native navigation, live download list, dialogs, details, queue, diagnostics, density/theme layout and status hierarchy. |
| Qt models | `native/src/models/DownloadModel.*` | Role-based `QAbstractListModel`, delta upsert/removal and model-backed task lookup/counts. |
| Controller | `native/src/services/TaskController.*` | UI-safe task selection/actions and presentation-facing projections of queue, profiles, bandwidth, stats and logs. |
| Daemon gateway | `native/src/adapter/CoreAdapter.*` | Sole authenticated HTTP/SSE access point; URL validation, request construction, parsing, error propagation and controlled reconnect. |
| Desktop/platform | `native/src/platform/DesktopService.*`, `native/src/main.cpp` | Safe file/folder actions, tray menu, persisted window geometry and application shell behavior. |
| Presentation settings | `native/src/services/SettingsService.*` | `QSettings`-backed palette mode, compact density, language preference and application layout direction. |

The QML layer does not manage bearer tokens, daemon routes or fake task data. Its visible records come from the C++ model, whose input is the actual daemon response or SSE delta.

## 3. Exact Core API Surface Used

| Functionality | Existing route used by NDM2 |
|---|---|
| Live task collection | `GET /api/downloads` |
| Real-time task changes | `GET /api/downloads/events` with authenticated SSE |
| Create task | `POST /api/downloads` |
| Metadata update | `PATCH /api/downloads/{id}` |
| Pause/resume | `POST /api/downloads/{id}/pause`, `POST /api/downloads/{id}/resume` |
| Retry | `POST /api/downloads/{id}/redownload` |
| Cancel/delete | `DELETE /api/downloads/{id}` with optional `deleteFiles=true` |
| Queue state/priority | `GET /api/engine/queue`, `POST /api/engine/queue` |
| Bandwidth | `GET /api/engine/bandwidth`, `POST /api/engine/bandwidth` |
| Profiles | `GET /api/engine/profiles`, `POST /api/engine/profiles` |
| Capability data | `GET /api/engines/capabilities` |
| Statistics | `GET /api/stats` |
| Daemon logs | `GET /api/logs?limit=n` |
| Scheduler bridge retained from Phase 1 | `POST /api/engine/scheduler/update` |

The adapter supplies the bearer token in C++ request headers. The SSE URL also uses the daemon-supported token query value for compatibility with that existing event contract; the token is never exposed to QML or stored in source files.

## 4. Real End-to-End Session Performed

A real NOVA binary was built from the preserved `src-tauri` source and started in its explicit integration mode on loopback with isolated test data. This test host is the genuine NOVA daemon, not a mock server. The test data and temporary download files were kept outside the repository.

| Test | Result | Evidence / observed outcome |
|---|---|---|
| Daemon authentication and health | Passed | Authenticated health and download routes returned live NOVA responses. |
| Real HTTPS download | Passed | A 10 MiB public test file was created, transferred to completion, and remained in Core state after NDM2 restarts. |
| Live SSE | Passed | Repeating `downloads-delta` events reported changing `downloadedBytes`, state and speed for the active task. |
| Pause | Passed | A deliberately throttled real transfer transitioned to `paused`. |
| Resume | Passed | The same task transitioned back to `downloading`. |
| Queue priority | Passed | `POST /api/engine/queue` returned the real priority change response. |
| Global bandwidth | Passed | Limit set to 256 KB/s then confirmed by `GET /api/engine/bandwidth`. |
| Cancel/delete | Passed | The active task was removed through the real delete/cancel route and verified absent from task state. |
| Failed-download retry | Passed | A true HTTP 404 task reached Core `error`; retry returned `queued` and then the Core re-entered resolving/downloading state before cleanup. |
| Metadata update | Passed | `PATCH` changed a completed task name; the original name was restored afterwards. |
| Profile switch | Passed | Core active profile changed to `economical`, was observed by read-back, then restored to `balanced`. |
| NDM2 restart persistence | Passed | Two sequential NDM2 Release launches connected to the same daemon; the completed test task remained in daemon state. |
| RTL/LTR startup | Passed (smoke) | English/dark and Arabic/light/compact persisted preferences both loaded the native application in headless mode. |
| Non-loopback endpoint handling | Passed | Native adapter preserved the loopback-only restriction. |

The initial 404 assertion ran before the Core’s resolver had finished and therefore saw `downloading`; a subsequent live query observed the expected `error` state with the 404 diagnostic. The retry result was then tested successfully. This timing detail is recorded to avoid overstating the test sequence.

## 5. Build and Regression Results

| Verification | Result |
|---|---|
| Debug Qt/CMake build | Passed. |
| Release Qt/CMake build | Passed. |
| Native app startup against live daemon | Passed in offscreen smoke mode after QML load validation. |
| Native app restart against live daemon | Passed twice; Core state was retained. |
| CTest discovery | Passed with **no CTest targets registered**. |
| Rust Core regression | `cargo test --manifest-path src-tauri/Cargo.toml --lib` passed: **712 passed, 0 failed**. |
| Rust Core preservation | `git diff --exit-code -- src-tauri` passed before and after the work. |
| Legacy frontend | Preserved; no React/Tauri UI files were removed. |

## 6. Remaining Migration Work

| Priority | Work still required before feature parity |
|---|---|
| High | Implement an actual Core-backed queue reordering experience once the daemon exposes or confirms its ordering contract; do not invent a client-side order. |
| High | Add scheduler list/read/edit workflow, simultaneous download limits, queue pause/start semantics, and richer global rate-limit management from confirmed routes. |
| High | Migrate profiles/rules/retry policy/mirrors/failover/checksum workflows in their complete Core-supported forms. |
| High | Add native media/playlist/format workflow, external-tools management, browser integration, notifications and Telegram configuration only behind the existing capability data. |
| High | Complete task properties: per-task diagnostics/traces, source alternatives, mirror state, checksums, adaptive/segment diagnostics and safe rename/source-edit UI. |
| Medium | Add Qt translation catalogs for Arabic, English, German, Hebrew and Persian. The direction logic exists, but the visible strings are not fully translated. |
| Medium | Perform visual/manual desktop tests for Windows, Linux and macOS tray behavior, keyboard navigation, screen readers, high-DPI scale, multi-monitor behavior, light theme and mixed RTL/LTR file strings. |
| Medium | Add proper native automated test targets for `DownloadModel`, SSE parsing and adapter contract behavior so CTest has executable coverage. |
| Medium | Remove remaining QML static-lint unqualified-access warnings by migrating context properties to typed QML registrations. |

## 7. Phase 2 Conclusion

Phase 2 makes NDM2 a more substantial native client for the existing NOVA daemon. The core data path is real, the event path is real, task actions map to existing daemon capabilities, and the principal integration sequence was tested with a genuine local NOVA daemon and actual network transfers. However, feature parity with the React/Tauri frontend has **not** been achieved. The old frontend remains required until the high-priority migration gaps and full desktop acceptance matrix are completed.
