# NDM2 Phase 4.1 — Native Desktop Acceptance Report

**Date:** 20 August 2026

**Scope:** Native C++20 / Qt 6 / Qt Quick client only

**Decision:** **Ready with documented limitations**

## Purpose and boundaries

Phase 4.1 performed a real desktop acceptance pass for the Phase 4 UX/UI implementation. The test client was launched through the X11 desktop backend on display `:0` under Openbox, rather than through the offscreen platform. It connected to the existing authenticated NOVA daemon on loopback and exercised actual daemon data, actual task operations, and actual Qt input events.

The pass did not modify `src/` or `src-tauri/`, did not introduce a listener, did not weaken authentication, and did not add mocks. All completed task data, metrics, queue values, health values, browser health values, and download state transitions came from the running NOVA daemon.

| Test environment | Value |
|---|---|
| Desktop display | X11 `:0`, 1280 × 1029 at 96 DPI |
| Window manager | Openbox |
| Qt runtime | Qt 6.4.2 |
| Renderer | Mesa llvmpipe software rendering |
| Daemon endpoint | Authenticated loopback NOVA daemon at `127.0.0.1:3199` |
| Core change scope | None in Phase 4.1 |

## Confirmed UX/UI corrections

The acceptance audit found and corrected several concrete client defects. The library subtitle used a QML-unavailable proxy-model `count` property and displayed `undefined`; it now binds to the actual `ListView.count`. Row actions previously attempted to invoke a non-invokable Q_PROPERTY writer, so selection now assigns `selectedId` correctly. The generic selection handler no longer opens the details drawer, preventing a right-click context menu from stacking with that drawer.

The settings dialog now has a bounded height and a vertical scroll container, so its lower content remains inside the dialog rather than spilling through the visual boundary. A themed ComboBox and CheckBox now provide explicit semantic surfaces, focus states, foreground text, and popup/delegate styling in the dark theme. A visible more-actions control that could not be proven operational on the real desktop was removed; the verified right-click context menu remains the context-action entry point.

| Area | Result after correction |
|---|---|
| Library count | Correctly reports `4 visible of 4 tasks from NOVA Core` in the final reconciled state. |
| Task selection and actions | Explicit property assignment works for library and Queue selection paths. |
| Details and context interaction | Double-click and `Ctrl+D` open details; right-click opens a state-aware menu without opening the drawer behind it. |
| Settings containment | Long settings content is clipped and scrollable inside the modal. |
| Dark-theme controls | Library filters, sorting and descending state use dark semantic control surfaces rather than bright default controls. |
| Status accessibility | Statuses continue to use both a symbol and a semantic color. |

## Real desktop acceptance

The main library was inspected at the declared minimum size of 980 × 650, an ordinary 1100 × 780 size, and the available maximized geometry of 1280 × 1008. The minimum-size view retained navigation, search, filters, rows, status badges, selection actions, connection state, and settings without overlap or a horizontal scrollbar. The 1100 × 780 view preserved the same hierarchy and readable spacing.

Light, Dark, and System theme selections were executed through the real Settings dialog. The host desktop resolved System to the light palette. The Dark screenshot after the themed-control correction confirmed readable ComboBoxes, chevrons, labels, and checked state. Arabic selection was also exercised through the Settings dialog. LayoutMirroring correctly placed navigation on the right, reversed toolbar and library ordering, and maintained readable Latin filenames, numbers, URLs, throughput, and ETA data. No Arabic translation catalog was present in the test environment, so interface strings remained English; this is a localization availability limitation rather than a right-to-left layout failure.

| Screen or workflow | Acceptance result |
|---|---|
| Main library and task rows | Pass, including empty, filtered, selected and completed states. |
| Add Download and details | Pass through real keyboard and mouse paths. |
| Queue | Pass with Core-backed empty-state summary and constrained action state. |
| Automation | Pass with guided editor, raw-schema entry point, scheduler and mirror tabs. |
| Media | Pass with real FFmpeg availability and no-metadata state. |
| Browser integration | Pass with disconnected bridge state and no exposed daemon token. |
| Diagnostics | Pass with live health, safe logs, capability and task-trace views. |
| Context menu | Pass through the verified right-click path. |

## Real NOVA workflow and reconciliation

A public 10 MiB ZIP URL was first checked using a headers-only request and was then entered through NDM2's `Ctrl+N` Add Download flow. NOVA created a real task named `10MB.zip`. The UI initially showed 0%, then showed 1.7 MiB of 10.0 MiB at 17% after eight seconds, and later showed 10.0 MiB of 10.0 MiB, 100%, and a completed badge. The surrounding library order remained stable while the row updated.

The completed task was opened in Details, where the client displayed the real source URL, completion state, size, four connections, four of four segments, zero retries, and the `libcurl-multi` engine. The task record was then deleted using the documented Delete shortcut with file deletion disabled. The task count returned from five to four and the client displayed the Core completion notice. After a fresh client restart, the library reconciled to exactly four tasks and did not restore the deleted test record.

| Real-operation step | Result |
|---|---|
| Create through Add Download | Pass |
| Observe incremental state | Pass: 0% → 17% → 100% |
| Complete file | Pass |
| Inspect drawer data | Pass |
| Delete task record without deleting file | Pass |
| Restart and reconcile daemon state | Pass |

## Keyboard, accessibility and security observations

The executed keyboard subset showed that `Ctrl+A` selects all visible Core tasks and reveals bulk actions, `Ctrl+D` opens the selected task's details, `Ctrl+N` opens the add workflow, `Ctrl+,` opens Settings, `Escape` closes active modal or drawer surfaces, and Delete removed the real test task record. With search focused, typing `p` appended to the query rather than invoking the global Pause shortcut, which confirms the focused-text input guard. Other documented shortcuts were not each independently exercised in the available completion-only task state and are not claimed as exhaustively validated.

The daemon listener remained bound only to `127.0.0.1:3199`. An unauthenticated request to the protected `/api/downloads` endpoint returned HTTP 401, while the existing Bearer-authenticated request returned HTTP 200. The public `/api/health` route returned HTTP 200 without a credential and is documented here as a health-check route, not as evidence that protected operations are unauthenticated. Screenshots and logs retained for this report do not contain the daemon token.

## Validation matrix

| Validation | Result |
|---|---|
| Debug configure and build | Pass |
| Qt model test suite | Pass: 1 / 1 (`NDM2ModelTests`) |
| Debug daemon smoke launch | Pass; application remained healthy for the expected timeout interval |
| Release configure and build | Pass |
| Release install to `dist/` | Pass |
| Installed Release daemon smoke launch | Pass; application remained healthy for the expected timeout interval |
| Rust Core unit suite | Pass: 712 / 712 |
| Diff whitespace check | Pass |
| Protected endpoint authentication check | Pass: 401 unauthenticated, 200 authenticated |

## Limits and deferred acceptance items

The available desktop was 1280 pixels wide and used llvmpipe software rendering. It therefore does not support a truthful high-DPI, hardware-GPU, or wider-than-screen visual claim. The available daemon history contained four tasks after cleanup, so no fabricated 100/500/1000-row performance result is included. A fresh launch reached a managed NDM2 window in 400 ms; approximately three seconds after launch, the process reported 207,272 KiB RSS and 23.7% CPU in the software-rendered environment. These are environment observations rather than product-wide benchmarks.

System tray support is not implemented in the current native client source, so no tray acceptance result is claimed. The visible user-facing more-actions button was removed because it failed real interaction probing; the supported context action remains right-click. Arabic layout is accepted, while Arabic string translation remains unavailable until translation resources are shipped. The test duration did not include a continuous 30–180 minute soak, network interruption/reconnection loop, or large-library benchmark; those items remain appropriate for a release-candidate or platform-matrix follow-up.

> **Readiness conclusion:** The Phase 4.1 native desktop client is ready for the tested authenticated loopback workflow with the documented environment and coverage limits. Its real add, progress, completion, details, deletion, restart reconciliation, desktop themes, layout mirroring, core pages, security boundary, and build/test paths all passed. The remaining items are explicit coverage or product-scope limitations, not hidden test successes.

## Evidence bundle

The following compact evidence set is retained under `docs/evidence/phase41/` for audit review. The full running observation log is `docs/phase41_visual_findings.md`.

| Evidence file | Demonstrates |
|---|---|
| `phase41_counter_fixed.png` | Correct library count after the QML binding fix. |
| `phase41_resize_minimum_valid.png` | Minimum supported desktop geometry. |
| `phase41_settings_scroll_fixed.png` | Contained, scrollable Settings dialog. |
| `phase41_theme_dark_controls_fixed.png` | Corrected dark standard controls. |
| `phase41_rtl_arabic.png` | Arabic RTL layout mirroring. |
| `phase41_context_final.png` | Final state-aware right-click action menu. |
| `phase41_real_download_live.png` | Newly created real task. |
| `phase41_real_download_completion_sample.png` | Real 100% completion state. |
| `phase41_completed_details.png` | Core-backed details drawer. |
| `phase41_completed_deleted.png` | Real deletion result. |
| `phase41_restart_reconciled.png` | State reconciliation after restart. |
| `phase41_diagnostics_page_valid.png` | Diagnostics and safe live telemetry. |
