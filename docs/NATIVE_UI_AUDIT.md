# NDM2 — Native UI Migration Audit

## Scope

NDM2 preserves the NOVA Rust download daemon and replaces only its Tauri/React presentation layer. The source repository was inspected before implementation. The new application is deliberately maintained in the `native/` subtree of NDM2 so the existing `src-tauri/` daemon, browser extension and installers remain available for compatibility and regression testing.

| Area | Finding | NDM2 decision |
|---|---|---|
| Desktop presentation | React/TypeScript under `src/`, hosted by Tauri | Replace with Qt 6 / Qt Quick / QML only. |
| Core | Rust daemon under `src-tauri/src/daemon` using libcurl multi and persistent state | Preserve without edits. |
| Existing desktop bridge | Tauri commands expose daemon URL/token and platform file operations | Recreate only the required host responsibilities in C++ and keep daemon traffic loopback-only. |
| Core API | Authenticated loopback HTTP API under `/api/*` plus download SSE events | Use a C++ `CoreAdapter` with bearer authentication. No QML network calls. |
| Download state | `DownloadItem` contains status, byte counts, speed, ETA, segments, paths, engine and options | Map live JSON into `QAbstractListModel` roles. |
| Capability model | `/api/health` and `/api/engines/capabilities` describe optional engine features | Gate controls from capability data; no simulated features. |
| Settings and languages | React settings stores and more than 100 locale resources exist | Persist native UI settings separately with `QSettings`, retaining core-owned settings through the daemon API. |
| Browser integration | Extension and native-messaging bridge are separate components | Retain source components unchanged; NDM2 does not rewrite them. |

## Verified Core/UI Contract

The existing client uses bearer-authenticated requests against the loopback daemon. The primary NDM2 adapter contract includes `GET /api/health`, `GET /api/engines/capabilities`, `GET/POST /api/downloads`, task pause/resume/redownload/delete endpoints, `/api/engine/queue`, `/api/engine/bandwidth`, `/api/engine/scheduler/update`, diagnostics, logs and media/external-tool endpoints. Download changes are represented by full or delta SSE payloads in the existing client; NDM2 initially uses coalesced authenticated polling in its adapter, which is compatible with the same core payload without exposing credentials to QML.

## Deliberately Untouched Components

The migration does **not** change the Rust download engine, libcurl configuration, segmentation, retries, scheduler, rules, profiles, priority queue, bandwidth manager, metadata cache, security checks, token model, external tools, browser extension, native messaging, Tauri daemon implementation or installer logic. Any future adapter addition must remain an additive UI-facing bridge and be documented.
