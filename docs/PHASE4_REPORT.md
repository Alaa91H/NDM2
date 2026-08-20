# NDM2 — Phase 4 UX/UI Excellence Report

**Date:** 20 August 2026  
**Scope:** Native C++20 / Qt 6 / Qt Quick client only  
**Core boundary:** The NOVA Rust Core, loopback authentication boundary, and preserved `src/` / `src-tauri/` legacy frontend were not modified during this phase.

## Purpose

Phase 4 transforms the functional NDM2 client into a coherent desktop product without introducing synthetic state or unsupported controls. The work establishes a semantic Qt Quick design system, makes the download library easier to scan and operate, improves the primary add/details workflows, and aligns secondary pages with the same information hierarchy. All operational actions still reach the existing authenticated `TaskController` and NOVA daemon paths.

| Design objective | Delivered result |
|---|---|
| Coherent native desktop presentation | A shared theme, typography scale, spacing scale, radii, semantic surfaces, focus treatments, and light/dark colors are defined in [`Theme.qml`](../native/qml/components/Theme.qml). |
| Unambiguous task state | [`StatusBadge.qml`](../native/qml/components/StatusBadge.qml) renders every state with **both a color and a symbol**. |
| Consistent actions | [`ActionButton.qml`](../native/qml/components/ActionButton.qml) establishes primary, secondary, danger, and quiet action tones with hover, focus, disabled, and accessible-name handling. |
| Better library scanning | [`DownloadRow.qml`](../native/qml/components/DownloadRow.qml) prioritizes filename, progress, current throughput, ETA, status, task metadata, and clear error text. |
| Native usability | Keyboard access, selection-aware bulk actions, context actions, focus treatments, and accessible labels have been expanded through the QML client. |

## Design system

The system replaces isolated visual constants on the redesigned surfaces with reusable semantic roles. It supports the existing `SettingsService` light, dark, and system themes; no theme setting was added outside the existing service. `LayoutMirroring` remains enabled at the root application window, so Arabic, Hebrew, and Persian continue to receive first-class right-to-left layout mirroring.

| Token family | Roles now available | Primary consumers |
|---|---|---|
| Surface and text | Background, sidebar, surfaces, borders, primary/secondary/muted text, selection | Main shell, pages, dialogs, details drawer |
| Semantic state | Accent, success, warning, danger, information and their soft variants | Status badges, diagnostics, media capabilities, offline states |
| Geometry | XS–XL spacing and small/medium/large radii | Navigation, cards, rows, dialogs, page sections |
| Typography | Meta, caption, body, large body, section, page and metric scales | Page headings, library metadata, diagnostics, dialog content |

The shared `SectionHeader` component provides a compact title/subtitle/action structure for Queue, Automation, Media, Browser Integration, and Diagnostics pages. `EmptyState` now has semantic `empty`, `offline`, `loading`, and `error` presentation paths with a symbol, color, explanation, and optional action instead of a single generic card.

## Primary workflow improvements

### Download library

The main window now uses a clearer three-level hierarchy: navigation and authenticated Core status in the sidebar, page-level search and create controls in the toolbar, and selection-aware filters/actions directly above the library. Rows expose context-sensitive pause, resume, retry, cancel, delete, and details entry points. A right-click menu mirrors the operational actions, without adding controls that lack a Core route.

The selected-task panel and row-level context actions operate through the existing `TaskController` commands. Status display uses the shared badge, and error messages are given a separate high-contrast line rather than being folded into ordinary metadata.

### Add download

[`AddDownloadDialog.qml`](../native/qml/dialogs/AddDownloadDialog.qml) now puts the required URL first, automatically focuses it on opening, and submits with Enter when valid. Filename, category, destination, and immediate start remain visible as the normal task contract. Connections, task bandwidth limit, and active profile are placed behind a **“Show supported advanced options”** disclosure. The dialog explicitly says that only daemon-supported fields are sent and leaves unsupported options absent.

### Details drawer

[`DetailsDrawer.qml`](../native/qml/dialogs/DetailsDrawer.qml) now begins with title, source URL, status badge, progress, transferred/total bytes, speed, and ETA. Its Overview, Speed, File, Mirrors, and Logs tabs preserve real task, trace, media, and mirror data. File and folder actions remain disabled until Core supplies a save path. The speed graph now accepts semantic line and grid colors so it remains readable in light and dark themes.

## Keyboard, accessibility, and feedback

The following shortcuts are implemented in `Main.qml` and invoke existing commands only. Single-letter actions are disabled while the search or modal dialogs hold focus so that text entry is not intercepted.

| Shortcut | Behavior |
|---|---|
| `Ctrl+N` | Open Add Download |
| `Ctrl+F` | Open the library if needed and focus search |
| `Ctrl+,` | Open Settings |
| `Ctrl+A` | Select all downloads visible under the current filter |
| `Ctrl+I` / `Ctrl+D` | Open selected download details |
| `Ctrl+P` / `P` | Pause the selected download |
| `Ctrl+R` / `R` | Resume the selected download |
| `Space` | Toggle pause/resume according to the selected task state |
| `O` | Open the selected file when Core reports a save path |
| `Delete` | Delete selected tasks without file removal |
| `F5` | Refresh current Core-backed data |
| `Escape` | Close details or clear selection |

Interactive system controls carry accessible names, including navigation items, reusable actions, download row controls, search, selection controls, add-download fields, settings choices, diagnostics level controls, and details sections. Statuses satisfy the required non-color-only representation through the shared badge symbols such as `↓`, `✓`, `⋯`, `Ⅱ`, `!`, `×`, and `◷`.

## Secondary pages

Queue, Automation, Media, Browser Integration, and Diagnostics all receive the shared section hierarchy and semantic colors. The pages preserve their existing Core-backed schemas and actions:

| Page | UX changes | Functional boundary retained |
|---|---|---|
| Queue | Summary cards, queue row status, semantic empty/offline state, priority action | Ordering remains intentionally unavailable until a verified Core route exists. |
| Automation | Shared header and validation-state color integration | Guided and raw editors retain the exact current rule/scheduler contracts. |
| Media | Shared header, primary probe/create actions, selected-format hierarchy, FFmpeg state color | Only formats returned by the existing NOVA media probe are selectable. |
| Browser integration | Shared header and compact live bridge health card | The preserved extension/native-messaging flow remains responsible for installation and authentication. |
| Diagnostics | Shared header, semantic safe-log levels, accessible log-level selector | Safe log scrubbing and Core-provided task trace/capability data remain unchanged. |

## Changed native client files

| Area | Files |
|---|---|
| QML module registration | `native/CMakeLists.txt` |
| System components | `Theme.qml`, `ActionButton.qml`, `SectionHeader.qml`, `StatusBadge.qml`, `EmptyState.qml`, `SpeedGraph.qml` |
| Application shell and library | `Main.qml`, `NavItem.qml`, `DownloadRow.qml` |
| Core-backed dialogs | `AddDownloadDialog.qml`, `DetailsDrawer.qml`, `SettingsDialog.qml` |
| Core-backed pages | `QueuePage.qml`, `AutomationPage.qml`, `MediaPage.qml`, `IntegrationPage.qml`, `DiagnosticsPage.qml` |

## Validation

All validation was executed after the final QML changes on 20 August 2026.

| Check | Command / method | Result |
|---|---|---|
| Debug configuration and build | `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build -j2` | Passed |
| Native Qt unit tests | `ctest --test-dir build --output-on-failure` | Passed: `NDM2ModelTests`, 1/1 |
| Debug daemon smoke test | `QT_QPA_PLATFORM=offscreen ./build/native/NDM2` with authenticated loopback endpoint/token | Passed: remained running until timeout with no QML runtime error |
| Release configuration and build | `cmake -S . -B build-release -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-release -j2` | Passed |
| Release install | `cmake --install build-release --prefix dist` | Passed: `dist/bin/NDM2` installed |
| Release daemon smoke test | `QT_QPA_PLATFORM=offscreen ./dist/bin/NDM2` with authenticated loopback endpoint/token | Passed: remained running until timeout with no QML runtime error |
| Rust Core regression suite | `cargo test --manifest-path src-tauri/Cargo.toml --lib` | Passed: 712/712 |
| Scope and whitespace check | `git diff --check` and path review | Passed: modified paths are native client/build/report files only |

> The offscreen smoke tests intentionally stop after eight seconds. A timeout exit in this test means the GUI stayed alive; it is treated as success only when the log contains no QML load or runtime error.

## Acceptance statement

Phase 4 delivers a native, non-IDM visual language while preserving the existing daemon as the sole operational authority. No mock library state, fake progress, unverified scheduling controls, weakened authentication, or legacy frontend removal was introduced. The Debug and Release artifacts build successfully, the installed client starts against the authenticated loopback daemon, and the existing Rust Core suite remains fully green.
