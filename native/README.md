# NDM2 Native Desktop UI

NDM2 is the native presentation layer for NOVA Download Manager. It is implemented with **C++20, Qt 6, Qt Quick and QML**. The implementation lives entirely in `native/`; it neither replaces nor edits the Rust daemon under `src-tauri/`.

> **Security boundary:** QML has no HTTP implementation and never receives the daemon bearer token. All daemon requests are issued only by `CoreAdapter` in C++, which permits `localhost`, `127.0.0.1`, and `::1` endpoints only and attaches the token as a bearer credential.

## Architecture

| Layer | Location | Responsibility |
|---|---|---|
| Qt Quick presentation | `qml/` | Native screens, dialogs, design tokens, keyboard actions, state views, RTL mirroring. |
| Application services | `src/services/` | Selection, task actions, presentation settings and coalesced speed samples. |
| Data models | `src/models/` | Efficient `QAbstractListModel` roles for the live download collection. |
| Core adapter | `src/adapter/` | Authenticated loopback requests to the existing NOVA daemon; capability discovery and timed refresh. |
| Desktop integration | `src/platform/` and `main.cpp` | Native directory picker, shell file actions, system tray, native menu and persisted window geometry. |

The primary model is refreshed every 1.2 seconds. It resets the model with the real array returned by `GET /api/downloads`; no fabricated download data or artificial progress is used. QML renders only model roles supplied by that adapter.

## Core Contract Implemented

| Operation | Existing daemon route | Exposure in NDM2 |
|---|---|---|
| Download collection | `GET /api/downloads` | Live `DownloadModel`, filterable table, details drawer and speed graph. |
| Create download | `POST /api/downloads` | Native Add Download dialog. |
| Pause and resume | `POST /api/downloads/{id}/pause`, `/resume` | Toolbar, shortcut and contextual selected-task actions. |
| Retry | `POST /api/downloads/{id}/redownload` | Toolbar and details action. |
| Cancel/delete | `DELETE /api/downloads/{id}` | Toolbar action; the adapter supports the core `deleteFiles` query flag. |
| Queue priority | `POST /api/engine/queue` | `TaskController::setSelectedPriority`. |
| Global bandwidth | `POST /api/engine/bandwidth` | Native settings dialog. |
| Scheduler update | `POST /api/engine/scheduler/update` | Adapter method, ready for the dedicated scheduler page. |
| Capability discovery | `GET /api/engines/capabilities` | Adapter-owned capability map for gated UI work. |

The adapter intentionally retains the original daemon’s authentication, loopback and capability decisions. It does not open a direct arbitrary network path from the UI.

## Prerequisites

| Component | Minimum version |
|---|---:|
| C++ compiler | C++20-capable compiler, such as GCC 11, Clang 14 or MSVC 2022 |
| CMake | 3.21 |
| Qt | 6.4, including Core, Gui, Network, Quick, Quick Controls 2 and Widgets |
| NOVA Core | Matching `src-tauri` daemon build or an installed NOVA daemon reachable on loopback |

On Ubuntu/Debian, a development environment can be installed with the distribution packages for `cmake`, `ninja-build`, `g++`, `qt6-base-dev` and `qt6-declarative-dev`, plus their Qt Quick runtime modules.

## Build

Build from the NDM2 repository root:

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j2
```

For a release build:

```bash
cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j2
cmake --install build-release --prefix dist
```

The Linux debug binary is written to `build/native/NDM2`.

## Run Against the Existing Core

NDM2 expects the already-running NOVA daemon and uses its normal bearer token. Prefer environment variables so the token is not saved in command history:

```bash
export NOVA_DAEMON_URL=http://127.0.0.1:3199
export NOVA_DAEMON_TOKEN='token-issued-by-the-existing-nova-host'
./build/native/NDM2
```

Equivalent command-line options are available for controlled development use:

```bash
./build/native/NDM2 \
  --daemon-endpoint http://127.0.0.1:3199 \
  --daemon-token "$NOVA_DAEMON_TOKEN"
```

Only loopback endpoints are accepted. A non-loopback endpoint is rejected before the application sends a request.

## Current Migration Scope

The implementation provides a functional native foundation: a live task table, add/pause/resume/cancel/retry/delete actions, details inspection, real values for size/speed/ETA/connections/segments/errors, persisted presentation preferences, light/dark/system presentation selection, RTL layout mirroring, keyboard shortcuts, system tray integration, native folder selection and safe file/folder shell actions.

The remaining NOVA feature surface—complete queue editing with drag-and-drop persistence, scheduler editor, profiles/rules/mirrors, checksum workflows, diagnostics/log explorer, media format chooser, external-tool management, browser handoff, desktop notifications and complete translation catalogs—must be added as capability-gated native pages before NDM2 can claim full functional parity. None of those omissions change the existing Rust Core.

## Test Notes

The build is validated with CMake/Ninja. A headless smoke test can verify that QML loads while safely targeting an unavailable loopback port:

```bash
timeout 5s env QT_QPA_PLATFORM=offscreen \
  ./build/native/NDM2 \
  --daemon-endpoint http://127.0.0.1:65530 \
  --daemon-token smoke-test-token
```

This checks application startup only; it is not proof of a live Core integration. Full end-to-end validation requires a running NOVA daemon with its authentic token and real downloadable test URLs.
