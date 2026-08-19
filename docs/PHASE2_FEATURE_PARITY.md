# NDM2 Phase 2 — Feature Parity Checklist

**Status convention:** **Implemented (adapter)** means the native UI has an implemented route wrapper but has not yet been proven against a live daemon in this phase. **Partial** means a real data/action path exists but the complete legacy workflow is not represented. **Planned** means no native equivalent exists yet. No entry is treated as complete until a genuine NOVA daemon test succeeds.

| Existing NOVA feature | Legacy UI location | Existing Core/API surface | NDM2 native equivalent | Phase 2 status | Required verification |
|---|---|---|---|---|---|
| Download library | Main React application and task store | `GET /api/downloads`, download events | `DownloadModel` and native list | Partial | Real daemon list, large library and delta updates. |
| Add direct download | `AddDownloadDialog` | `POST /api/probe`, `POST /api/downloads` | Native Add Download dialog | Partial | Probe metadata and test each supported option. |
| Pause | Toolbar/task controls | `POST /api/downloads/{id}/pause` | Native selected-task action | Implemented (adapter) | Pause a real transfer. |
| Resume/start | Toolbar/task controls | `POST /api/downloads/{id}/resume` | Native selected-task action | Implemented (adapter) | Resume a real paused transfer. |
| Cancel | Toolbar/task controls | `DELETE /api/downloads/{id}` | Native selected-task action | Implemented (adapter) | Cancel a real transfer. |
| Retry | Task controls | `POST /api/downloads/{id}/redownload` | Native selected-task action | Implemented (adapter) | Retry a real failed transfer. |
| Delete/files | Task controls | `DELETE /api/downloads/{id}?deleteFiles=true` | Native action supports `deleteFiles` flag | Partial | Confirm/remove dialog and real filesystem behavior. |
| Open/reveal | Task controls | Existing safe desktop host operations | `DesktopService` | Partial | Verify paths issued by real core on each platform. |
| Rename/update source | `RenameDialog`, `UpdateLinkDialog` | `PATCH /api/downloads/{id}` | None | Planned | Add real property editor. |
| Task properties/details | `TaskPropertiesDialog` | Task JSON, adaptive/segments/log endpoints | Details drawer | Partial | Add sources, statistics and logs from real calls. |
| Queue overview | Queue store/UI | `GET /api/engine/queue` | None | Planned | Implement native queue model and view. |
| Queue priority | Queue UI | `POST /api/engine/queue` | Adapter method | Implemented (adapter) | Set and observe priority in real core. |
| Queue drag/drop order | Queue UI | Core queue state/API | None | Planned | Identify order endpoint and persist a real reorder. |
| Queue pause/start/limits | Queue UI | Queue and bandwidth APIs | None | Planned | Add only confirmed core controls. |
| Scheduler | `SchedulerPage` | `/api/engine/scheduler/update` | Adapter method only | Partial | Add list/read and edit workflow from confirmed route shape. |
| Global/task bandwidth | Settings and task controls | `/api/engine/bandwidth`, `/api/engine/rate-limit` | Global bandwidth setting | Partial | Read, set and persist against real daemon. |
| Profiles | Settings/download UI | `/api/engine/profiles` | None | Planned | Add capability-gated profile selector. |
| Retry policy | Settings | `/api/engine/retry-policy` | None | Planned | Native policy editor. |
| Download rules | Settings/rules | Core rule endpoints | None | Planned | Map legacy route contract, then implement. |
| Mirrors/failover | Properties/settings | `/api/engine/mirrors*` | None | Planned | Native mirror workflow. |
| Checksum | Properties | Existing core task/checksum state | None | Planned | Discover actual task contract and add read-only/result UI. |
| Diagnostics | `DiagnosticsDialog` | `GET /api/diagnostics`, logs routes | None | Planned | Native diagnostics/log explorer. |
| Media download | `MediaDownloadPage` | yt-dlp probe/playlist/FFmpeg routes | None | Planned | Capability-gated media wizard. |
| External tools | Settings section | `/api/external-tools*` | None | Planned | Native tools management page. |
| Browser integration | `BrowserIntegrationDialog` | browser extension health/config | None | Planned | Native browser integration page. |
| Telegram integration | Settings section | Telegram config/test/send routes | None | Planned | Native integration page. |
| Themes | Appearance settings | Local UI choice | `SettingsService` and QML palette | Partial | Ensure light/system palette complete and persistent. |
| Languages | Existing locale catalog | Local UI choice | direction selection only | Partial | Migrate/load real Qt translation catalogs. |
| RTL/LTR | Existing React i18n | Qt direction/layout system | `LayoutMirroring` | Partial | Arabic/German/LTR and mixed-content manual tests. |
| System tray | Tauri/desktop integration | Core state plus host tray | Native `QSystemTrayIcon` | Partial | Add real summary and pause/resume actions. |
| Notifications | Desktop UI | Existing native capability | None | Planned | Capability and platform-aware notifications. |
| Settings | Multiple settings sections | Core plus local UI state | Appearance + bandwidth only | Partial | Migrate settings by core ownership and semantics. |

## Audit Conclusions

The current native foundation correctly isolates core access, uses true daemon payloads for the central list, and provides core-backed basic actions. The largest migration gaps are queue management, complete details/properties, scheduler/profiles/rules/mirrors, diagnostics, media and browser integration. Phase 2 must preserve the React/Tauri frontend while those capabilities are migrated and verified against a live daemon.
