# Phase 4.1 — Visual Findings Log

## Environment evidence

- Display: X11 `:0`, 1280 × 1029 pixels, 96 DPI.
- Rendering: Mesa llvmpipe software renderer (no hardware acceleration reported).
- Qt: 6.4.2.
- Window manager for validation: Openbox.
- Application was launched with the normal X11 backend on the real display, not `QT_QPA_PLATFORM=offscreen`.

## Main-window inspection at maximized 1280 × 1029

| Item | Result | Evidence |
|---|---|---|
| Window launches as a native desktop window | Pass | `wmctrl` reported a 1440 × 900 NDM2 window; root screenshot captured it via X11. |
| Main shell / sidebar / toolbar | Pass | All are visible with no overlap in `phase41_desktop_main.png`. |
| Library rows, badges, selection treatment, filters, connection panel | Pass | Four real Core tasks were visible; status badges show both the check symbol and completed label/color. |
| Initial counter | Defect found | The subtitle read `undefined visible of 4 tasks from NOVA Core` in `phase41_desktop_main.png`. |
| Root cause | Confirmed | `Main.qml` referenced `taskController.filteredDownloads.count`, but the proxy model does not expose QML `count`. |
| Fix | Applied | Replaced that expression with `list.count`, the actual ListView count. |
| Regression check | Pass | `phase41_counter_fixed.png` reads `4 visible of 4 tasks from NOVA Core`; no runtime QML error appeared in the desktop log. |

## Scope note

The screenshots intentionally remain as evidence artifacts for the Phase 4.1 report. Further tests will record only observations actually exercised on this X11/Openbox environment. High-DPI, hardware-GPU, and system-tray conclusions remain untested at this point.

## Details and context-menu inspection

| Item | Result | Evidence |
|---|---|---|
| Opening a task through a real row interaction | Pass after task-selection bridge fix | `phase41_context_fixed.png` shows the real selected task in the details drawer: title, URL, completed badge, progress, Overview metrics, and Core engine. |
| Details data source | Pass | The drawer showed a daemon-provided 10.0 MB task, its Core URL, connection count, segments, retries, and `libcurl-multi` engine. |
| Context menu appears from real right click | Pass | `phase41_context_fixed.png` shows Open details, Cancel (correctly disabled for a completed task), and Delete. |
| Context action state | Pass | State-aware menu omitted pause/resume/retry on the completed task and disabled Cancel. |
| Context-menu / drawer interaction | Defect found | Right-click selection also triggered the global `onSelectedChanged` handler, opening the details drawer behind/alongside the row context menu. This produces an unintended stacked interaction. |
| Root cause | Confirmed | `Main.qml` opens the drawer for every `selectedChanged` signal, including the selection made to invoke a context menu. |
| Planned narrow fix | Remove automatic drawer opening on generic selection; preserve explicit drawer opening from double-click, context `Open details`, and documented shortcuts. |

The first double-click screenshot was captured before the drawer became visible, while the subsequent interaction confirms that the drawer itself does open and is Core-backed. The interaction audit will re-test explicit double-click after the narrow selection-handler correction.

## Re-test after selection-handler correction

| Item | Result | Evidence |
|---|---|---|
| Explicit double-click opens details | Pass | `phase41_details_explicit.png` shows the 1Mb.dat drawer fully open after a genuine mouse double-click. |
| Explicit details layout | Pass | The window retained readable library content and the drawer showed Core-backed overview data without overlap. |
| Generic selection no longer opens drawer | Pass | `phase41_context_isolated.png` shows the selected last row and bulk-action strip without a details drawer. |
| Right-click menu in isolated re-test | Inconclusive / defect candidate | The isolated screenshot does not contain the expected menu, despite the row becoming selected. Earlier `phase41_context_fixed.png` did show the menu, but it was stacked with the drawer. This must be investigated with event-level evidence before classifying it as a fixed interaction. |

No QML runtime error was emitted in the re-test log.

## Context-menu follow-up

| Item | Result | Evidence |
|---|---|---|
| Isolated physical-style right-click | Did not show a menu | `phase41_context_diagnosis.png` shows no menu after an explicit X11 button-3 press/release on a row. |
| Row more-actions control | Did not show a menu | `phase41_more_actions.png` shows the tooltip for the visible `⋮` control after a left click, but no action menu. |
| Current assessment | Confirmed interaction defect | The menu had been visible before the selection-handler change, but does not open reliably under the actual desktop sequence. Both visible access paths must be considered defective until fixed and re-tested. |

The tooltip proves the more-actions control itself is present and hovered; it does not prove its click handler opened the menu. No additional claim is made about the root cause until the QML path is corrected and tested again.

## Context-menu anchor correction re-test

| Item | Result | Evidence |
|---|---|---|
| Right-click row menu | Pass | `phase41_context_anchor_fixed.png` shows the completed-task menu at the click position, with Open details, disabled Cancel, and Delete. |
| Drawer suppression during right-click | Pass | The drawer is absent from the right-click screenshot; the selection-only correction remains effective. |
| More-actions `⋮` menu | Defect remains | `phase41_more_actions_fixed.png` shows the control hover tooltip but not a menu. The menu call must use the working row-level parent/coordinates rather than the ToolButton as its popup parent. |
| Narrow follow-up fix | Planned | Re-anchor the visible-button path to `rowMouse` using a menu-width-safe right-edge position, then retest both access paths. |

## More-actions final probe in this environment

| Item | Result | Evidence |
|---|---|---|
| Right-click context menu | Pass | Still shown after explicit row-relative `Menu.popup` anchoring. |
| Visible `⋮` more-actions control | Not validated as working | Neither the row-relative `onClicked` nor the `onPressed` probe produced a visible menu in `phase41_more_actions_row_anchor.png` or `phase41_more_actions_pressed.png`; both show only the hover tooltip. |
| Reporting decision | Limitation / remaining defect | The right-click access path is usable and Core-state-aware. The visible more-actions affordance remains a verified non-working path in this X11 test sequence and must not be reported as passed. Further redesign is outside the minimal scope unless an implementation-level cause is isolated. |

## Final visible-more-actions attempt

The explicit MouseArea replacement and matching row-selection setup did not yield a visible popup in `phase41_more_actions_mousearea.png` or `phase41_more_actions_final.png`. The element remains hoverable and carries an accessible name, but the action menu was not observed. The real right-click path is confirmed working and remains the usable context-menu path. This is retained as a **remaining visible-control defect** for the Phase 4.1 readiness decision rather than being silently treated as passed.

## Resize-audit evidence correction

The first resize artifact (`phase41_resize_minimum.png`) captured Chromium, not NDM2. The attempted `xdotool search --name NDM2 | tail -n1` selected a Qt selection-owner helper window after several prior desktop launches, not the managed top-level NDM2 window. Therefore **none of the first three resize screenshots is counted as NDM2 visual validation**. The process accumulation and ambiguous window targeting are test-harness issues, not an application resizing conclusion. The next attempt will terminate the agent-launched client processes, launch exactly one client instance, identify its main window through `wmctrl` by title/class and geometry, and only then resize it.

## Valid window-resize audit

| Geometry exercised | Result | Actual observation |
|---|---|---|
| Minimum declared window size: 980 × 650 | Pass | `phase41_resize_minimum_valid.png` shows the main navigation, search, filters, all four rows, status badges, bulk affordances, connection panel, settings action, and footer without overlap or horizontal scrollbar. Long secondary task text is correctly elided rather than spilling. |
| Normal window: 1100 × 780 | Pass | `phase41_resize_normal_valid.png` shows expanded horizontal spacing and preserves the same primary hierarchy without clipping or inaccessible controls. |
| Maximum available desktop geometry: 1280 × 1008 | Captured; visual baseline already inspected | The real display is 1280 × 1029 and the Openbox-managed NDM2 window finished at 1280 × 1008. |

The visual audit was limited by the available 1280-pixel-wide display: a wider-than-screen desktop geometry could not be exercised truthfully.

## Settings-dialog inspection

| Item | Result | Evidence |
|---|---|---|
| Settings opens with the documented shortcut | Pass | `phase41_settings_dialog.png` shows the native modal opened via `Ctrl+,`. |
| Theme, density, language, profile, bandwidth, retry, notifications controls | Visible and laid out | The controls are present with readable labels in the modal. |
| Dialog vertical content containment | Defect found | The lower integration/diagnostics text extends below the rounded dialog boundary in `phase41_settings_dialog.png`. The dialog calculates an insufficient content height and has no scroll containment. |
| Narrow fix | Planned | Give the dialog a bounded desktop height and make its settings grid vertically scrollable. This fixes overflow without adding settings or changing Core behavior. |

## Settings overflow fix and Light theme

| Item | Result | Evidence |
|---|---|---|
| Settings containment after scroll fix | Pass | `phase41_settings_scroll_fixed.png` keeps all visible settings content within the modal rounded boundary; the dialog no longer renders content outside itself. |
| Light theme via Settings UI | Pass | `phase41_theme_light.png` was captured after selecting Light in the actual Theme combobox. Toolbar, selected row, status badges, secondary text, borders, and empty library area remain readable. |

The Settings dialog was closed through Escape after selecting the theme, exercising the modal exit path as well.

## Dark-theme inspection

| Item | Result | Evidence |
|---|---|---|
| Main surfaces, sidebar, selection, status badges, primary actions | Pass | `phase41_theme_dark.png` shows the semantic dark surface and still-readable status badges / primary action. |
| Default Qt controls in dark theme | Defect found | The category, queue, and sort ComboBoxes remain bright white; the Descending label is very low contrast. This violates the semantic theme expectation and creates inconsistent dark-mode controls. |
| Root cause | Confirmed | The design tokens styled custom components, but no application-level `Palette` was assigned to inherited Qt Quick Controls. |
| Narrow fix | Planned | Define the semantic Qt control palette on the existing `ApplicationWindow` so standard ComboBox, CheckBox, text-field, menu, and dialog controls inherit light/dark roles without replacing their functionality. |

## Palette follow-up

The application-level `Palette` compiles and is semantically correct, but `phase41_theme_dark_palette_fixed.png` shows that the active Qt Quick Controls platform style still renders the three library ComboBoxes with bright white surfaces and leaves the Descending label near-black. The standard-control dark-theme defect therefore remains **open**; the palette-only correction is insufficient in this runtime style and is not counted as a successful fix.

## Theme audit completion

| Mode | Result | Evidence |
|---|---|---|
| Dark after explicit themed controls | Pass | `phase41_theme_dark_controls_fixed.png` shows dark semantic ComboBox surfaces, light readable labels, chevrons, and a blue checked Descending control. The previously white/near-black controls are corrected. |
| System | Pass in this desktop session | `phase41_theme_system_restored.png` was captured after selecting System in Settings. The host session resolved System to the light palette, with the themed filters and checkbox preserving appropriate contrast. |

Theme selection was returned to **System** after the audit. No theme-specific QML runtime error was emitted.

## RTL/LTR audit

| Item | Result | Evidence |
|---|---|---|
| Arabic language selection path | Exercised | The RTL capture was produced after selecting `ar` from the actual Settings language combobox. |
| Layout mirroring | Pass | `phase41_rtl_arabic.png` shows the sidebar on the right, toolbar action ordering mirrored, column ordering mirrored, selection controls/file glyphs on the right of rows, status badges on the left, and footer connection information mirrored. |
| Mixed Latin task data | Readable | English filenames, URLs/metadata, numbers, percentages, throughput and ETA placeholders remained readable in their mirrored row context. |
| Arabic textual localization | Not validated / unavailable | UI strings remained English in the Arabic session because no Arabic translation catalog was loaded in this environment. This is documented as a localization availability limitation, not a LayoutMirroring failure. |

The language was restored to English through Settings after the RTL capture.

## Navigation-audit correction and RTL Settings

The screenshots originally named for Queue and other secondary pages are **not counted as page-validation evidence**. In the still-active RTL session, the sidebar was on the right, while the scripted x-coordinates targeted the left side of the library. `phase41_queue_page.png` therefore shows the mirrored library rather than Queue.

`phase41_settings_rtl.png` provides additional RTL evidence: the dialog's Appearance column is mirrored to the right, Language and direction is mirrored to the left, the close control moves to the left, and the active language field visibly reports `ar` with `Right-to-left layout enabled`. No overlap or boundary overflow appears in this RTL modal.

## Queue page

`phase41_queue_page_valid.png` confirms that a real sidebar click opens Queue. The screen shows Core-backed summary values (`Active 0`, `Entries 0`, `Bandwidth 0 KB/s`, `Next —`), a clear empty queue state with an Add download action, and a disabled Set priority action because no task is selected. The page clearly states that ordering is withheld until NOVA exposes a verified route. No clipping or overlap was observed at the maximized desktop geometry.

## Automation and Media pages

| Page | Result | Actual observation |
|---|---|---|
| Automation | Pass | `phase41_automation_page_valid.png` shows the Core-backed Rules workspace with guided inputs, raw schema editor, contract note, tabs for Scheduler/Mirrors, and a disabled guided-add action until required input exists. No visual overlap occurred. |
| Media | Pass | `phase41_media_page_valid.png` shows URL/destination inputs, disabled Probe until URL entry, a positive live `FFmpeg available` capability, and an explicit no-metadata-yet state. No synthetic format rows were shown. |

## Browser Integration and Diagnostics

| Page | Result | Actual observation |
|---|---|---|
| Browser integration | Pass with expected bridge status | `phase41_browser_page_valid.png` shows the preserved bridge contract, a disconnected bridge status, no native-messaging value, extension version `2.4.2-alpha`, and the loopback endpoint `http://127.0.0.1:3199`. No token is rendered. |
| Diagnostics | Pass | `phase41_diagnostics_page_valid.png` shows live connected health, version, active/queue/bandwidth/profile/completed/failed metrics, safe HTTP log entries, and task-trace/capability tabs. It does not render the daemon token. |

Both pages opened through real sidebar interaction and had no visible clipping at the tested maximized geometry.

## Real authenticated download workflow

| Step | Result | Evidence |
|---|---|---|
| Submit a real URL through Add Download | Pass | A public 10 MiB ZIP URL was pre-checked with `curl -I` (HTTP 200, `Content-Length: 10485760`) and entered through `Ctrl+N` / Enter in NDM2. |
| Core creates a real task | Pass | `phase41_real_download_live.png` shows a new `10MB.zip` task, library count increasing from 4 to 5, Queue count increasing to 1, and the native toast `Core operation completed: create`. |
| Live state and incremental row update | Pass | The initial capture reports `downloading` at 0%; `phase41_real_download_settled.png` reports 1.7 MB / 10.0 MB and 17% on the same top row eight seconds later. The list stayed in place; prior rows retained their order and no full-list flicker was observed. |
| Completion | Not yet observed | The external source transferred slowly in this environment; at the eight-second sample it was still actively downloading. Completion and subsequent cleanup will be verified in a later sample. |

## Real download completion

`phase41_real_download_completion_sample.png` confirms that the same `10MB.zip` row reached **10.0 MB / 10.0 MB**, **100%**, and a completed status badge after the extended observation. The list remained stable and still reported five tasks. This closes the add → live progress → completion portion of the real daemon workflow.

## Details and deletion of the real test task

| Step | Result | Evidence |
|---|---|---|
| Open details after completion | Pass | `phase41_completed_details.png` shows the actual `10MB.zip` source URL, 100%, 10.0 MB/10.0 MB, completed badge, 4 connections, 4/4 segments, zero retries, and `libcurl-multi` engine. |
| Delete using documented shortcut | Pass | `phase41_completed_deleted.png` shows the library returning from 5 to 4 tasks and the native toast `Core operation completed: delete`. The deletion route passed `false` for file removal, so this validates task-record deletion only. |

This completes add → live progress → completion → inspect details → delete for a real authenticated daemon task.

## Restart reconciliation

`phase41_restart_reconciled.png` shows a fresh NDM2 process connected to the authenticated daemon and reconciling exactly four tasks. The completed 10MB test task remains absent after restart. This validates state reconciliation across the tested client restart.

## Keyboard audit (executed subset)

| Shortcut | Result | Evidence |
|---|---|---|
| `Ctrl+A` | Pass | `phase41_keyboard_select_all.png` shows all four visible Core tasks selected and the bulk Pause/Resume/Retry/Delete strip available. |
| `Escape` | Pass | Used after the bulk-selection capture to clear selection and close the details drawer in subsequent steps. |
| `Ctrl+D` | Pass | `phase41_keyboard_details.png` shows the details drawer opened for the selected 1Mb.dat task. |
| `Ctrl+N` | Pass | Used earlier to create the real 10MB test download. |
| `Ctrl+,` | Pass | Used repeatedly to open Settings for Light/Dark/System and language checks. |
| `Delete` | Pass | Used earlier to delete the completed real test task record. |

`Ctrl+I`, `Ctrl+P`, `Ctrl+R`, `Space`, `O`, and `F5` were not all independently evidenced in this completion-only task state; no claim of exhaustive keyboard conformance is made.

## Search-field shortcut protection

`phase41_keyboard_search_text.png` shows the search field focused with the exact entered text `1Mbp`. The final `p` was inserted into the field rather than invoking the global Pause action, which confirms the documented text-entry guard for this shortcut path. The filter yielded a real zero-result empty state; no list reset or synthetic placeholder was shown.

## Performance observations (actual environment)

- A fresh native X11 launch reached a managed NDM2 window in **400 ms**, measured from process spawn to first `wmctrl` detection.
- At approximately three seconds after launch, the process reported **207,272 KiB RSS** and **23.7% CPU** under Mesa **llvmpipe** software rendering.
- The daemon history available in this environment contained only **four** remaining tasks after cleanup. No 100/500/1000+ library benchmark was fabricated or claimed.
- During the real 10 MiB download update sequence, the row progressed from 0% to 17% to 100% while the library ordering remained stable. This is an observed incremental-update result at the tested scale only.

## Security regression check

| Check | Result |
|---|---|
| Listener binding | Pass: `nova` listened only on `127.0.0.1:3199`; exactly one listener matched the daemon port. |
| Protected operations endpoint | Pass: unauthenticated `GET /api/downloads` returned **401**; the same request with the existing Bearer credential returned **200**. |
| Health endpoint | Informational: `GET /api/health` returned **200** without a Bearer credential. This endpoint is a public health check; it was not treated as proof that protected operations are unauthenticated. |
| Client credential handling | Pass by source inspection: the adapter attaches `Authorization: Bearer …` only when a configured token is present. No token was included in screenshots or this report. |
| New listener / QML credential storage | No evidence introduced: Phase 4.1 changes are QML presentation/interaction components; no listener or credential storage was added. |

## Final context-action correction

The non-working visible `⋮` control was removed rather than left as a deceptive interactive affordance. `phase41_context_final.png` confirms that the explicit row right-click path still opens the state-aware menu for the selected completed task, exposing Open details, disabled Cancel, and Delete. The drawer does not open behind it. This closes the verified context-action interaction issue within the documented right-click workflow.
