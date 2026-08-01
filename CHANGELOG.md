# Changelog

All notable changes to NOVA Download Manager are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Root `LICENSE` (MIT) and `THIRD_PARTY_NOTICES.md` documenting bundled
  curl/libcurl, yt-dlp, and FFmpeg license obligations.
- Repository-standard governance files: `SECURITY.md`, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md`, and this `CHANGELOG.md`.
- License and third-party notices are staged into the installed application
  directory at build time (`scripts/build-tauri-assets.mjs`) and asserted by the
  final source audit (`scripts/final-audit.mjs`).

### Changed

- **Repository unification.** Centralized all repository policy at the root
  (`.gitignore`, `.gitattributes`, `.editorconfig`, `.npmrc`, `.prettierrc`,
  `.node-version`, `pnpm-workspace.yaml`) and moved all documentation except the
  root `README.md` under `docs/`. The browser extension is now a source-layout
  submodule with a single canonical lockfile and one CI/Dependabot control plane.
- Reconciled `.env.example` with the variables actually consumed by the app and
  tooling.

### Fixed

- **Adaptive engine is now live.** Decisions (split/merge/rebalance, connection
  redistribution) are applied to active easy handles with a debounced rebuild
  loop; `adaptive` (default on) and `adaptiveEvalMs` options added.
- **Pause actually pauses.** `RateLimit::{Unlimited,Limit,Paused}` and a pause
  gate in both drive loops stop bytes from moving while paused.
- **Live rate limits.** Bandwidth changes are pushed to running handles every
  tick instead of at handle creation; removed the implicit 500 B/s / 15 s
  low-speed abort that killed legitimate slow downloads.
- **Scheduler is edge-triggered** — Shutdown/Sleep/Notify fire once per
  condition instead of every 60 s tick; macOS sleep uses `pmset sleepnow`.
- **Honest capability reporting** — `hlsDashDownload` and `supportedRawOptions`
  now reflect reality.
- **Race-free telemetry** — `TelemetryBus` recomputes aggregates from slots;
  prefix-segment rebalance never re-downloads overlapped bytes; symmetric
  retry jitter; `ProfileStore` surfaces write errors; watchdog joins bounded.
- **Frontend** — `novaClient` works without `window`; translations loader is
  explicit; `bridgeStore` keeps degraded mode in sync; Polish locale encoding
  repaired.

### Notes

This is the first tracked changelog entry. Earlier history is captured in the
initial repository import.

## [0.1.0] - Unreleased

Initial development baseline:

- Tauri desktop shell with a React UI and an in-process Rust daemon.
- Direct-download engine using linked static `libcurl` (segmented byte-range
  downloads, generation-guarded pause/resume, atomic merge, runtime protocol and
  feature validation).
- Media engine via `yt-dlp` + FFmpeg with capability-gated post-processing.
- Manifest V3 browser companion with a local-only loopback + Native Messaging
  bridge and protocol v4.
- Branded Windows NSIS installer with full install/upgrade/repair/uninstall
  lifecycle and Native Messaging registration.
- Runtime capability gating across desktop UI, extension, and daemon.

[Unreleased]: https://github.com/Alaa91H/NovaDownloadManager/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Alaa91H/NovaDownloadManager/releases/tag/v0.1.0
