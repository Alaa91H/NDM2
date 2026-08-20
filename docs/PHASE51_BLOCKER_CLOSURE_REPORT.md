# NDM2 Phase 5.1 — Release Blocker Closure Report

**NDM2 version:** `3.0.0`

**Decision:** **NOT READY — BLOCKERS REMAIN**

## Daemon configuration and persistence mechanism

The NOVA daemon persistence mechanism is implemented by the existing Core. In the current Linux test configuration, the daemon uses `HOME/nova-download-manager` as its data directory and stores the authoritative snapshot in `downloads-state.json`. The file contains the persisted task collection. The Core starts a persistence loop and, on restart, reconstructs direct HTTP(S) jobs from that snapshot. Existing Core semantics deliberately restore running direct jobs as paused because the previous process's transfer workers do not survive a daemon restart.

The test used the current authenticated daemon process with the same persistent data directory across restart. It did not add client-side storage, modify the Rust persistence mechanism, or recreate missing rows in NDM2. The current `--integration` process remains a test harness rather than a final packaged production daemon launcher; the persistence evidence below proves the existing Core storage mechanism but is not a substitute for a deployed production-daemon installation test.

## Persistence and client-recovery evidence

Three real authenticated Core tasks were created: a completed 1 MiB transfer, a rate-limited active 10 MiB transfer, and a queued 1 MiB task. Structured JSON snapshots were recorded before and after daemon restart. All three UUIDs remained stable. The completed task remained completed. The active and queued tasks both returned paused, which matches the existing Core restart behavior. The `downloads-state.json` file contained all three tasks before restart.

NDM2 was then closed normally during the active task and restarted. It reconciled exactly the same three Core task IDs without creating a duplicate. NDM2 was also terminated with `SIGKILL` and restarted. Core snapshots before, while closed, and after restart contained three stable task IDs, while the real desktop client again rendered exactly three rows. The active transfer later entered a real Core error state because no data was received from its remote source for sixty seconds; this was shown accurately in NDM2 and did not remove or duplicate its task record.

| Blocker | Evidence | Result | Release blocking |
|---|---|---|---|
| Daemon task persistence | `before-daemon-restart.json`, `state-after-shutdown.json`, `after-daemon-restart.json` | Pass for current persistent Core data directory: 3/3 stable IDs | No for Core persistence mechanism |
| Active task across daemon restart | Same snapshots | Pass with Core semantic transition `downloading` → `paused` | No |
| Queued task across daemon restart | Same snapshots | Pass with Core semantic transition `queued` → `paused` | No |
| Completed task across daemon restart | Same snapshots | Pass: completed and ID stable | No |
| Normal NDM2 restart | `before-ndm2-normal-restart.json`, `while-ndm2-closed.json`, `after-ndm2-normal-restart.json` | Pass: no duplicate task record | No |
| Abnormal NDM2 termination | `before-ndm2-abnormal-termination.json`, `while-ndm2-killed.json`, `after-ndm2-abnormal-restart.json` | Pass: 3 stable IDs and 3 client rows | No |
| Network interruption, retry/resume and final integrity | External large-file sources failed SSL connection or timed out before an interruption test could begin | Not executed | **Yes** |
| Browser handoff regression | Browser endpoint reported `paired: false` / `status: disconnected`; no native-message handoff completed | Failed/unavailable | **Yes** |
| Media regression | FFmpeg was available, but current yt-dlp probe returned HTTP 504 `Probe timed out`; no format/job/file completion occurred | Failed/unavailable | **Yes** |

## Browser and media current results

The existing browser health endpoint was queried directly through the authenticated daemon. It reported that media facilities and FFmpeg routing were available, but the browser bridge was disconnected and unpaired. No browser extension to native messaging to Core transfer was therefore claimed.

FFmpeg was found at `/usr/bin/ffmpeg`. The current yt-dlp probe used a public YouTube test URL, but the daemon returned HTTP 504 with `Probe timed out`. No format discovery, media-job creation, download, resulting file, or false media success is claimed.

## Network interruption result

The existing public 10 MiB source initially provided real task data but later stalled. Alternative public large-file sources returned SSL connection failure or timeout from this environment before a transfer could begin. Because a real download with non-zero progress from a reliable source could not be established, no firewall or connection interruption was applied and no retry/resume or file-integrity result is claimed. This is an explicit unclosed release blocker, not a client-side workaround opportunity.

## Security and regression validation

The daemon listener remained bound to `127.0.0.1:3199`. The protected downloads endpoint returned HTTP 401 with an invalid Bearer value. No new listener was introduced. The clean Debug build passed with `NDM2ModelTests` at 1/1. The clean Release build passed, the Linux bundle was generated, and the extracted bundle launched from `/tmp` with isolated XDG paths while `build-release` was not used at runtime. The Rust Core library suite passed 712/712 tests.

| Validation | Result |
|---|---|
| Protected endpoint with invalid credential | Pass: HTTP 401 |
| Daemon listener | Pass: loopback-only `127.0.0.1:3199` |
| Clean Debug build and CTest | Pass: 1/1 |
| Clean Release build | Pass |
| Independent extracted Linux bundle launch | Pass for expected timeout interval |
| Rust Core library tests | Pass: 712/712 |
| Repository token scan for Phase 5.1 evidence | Must be re-run immediately before any future RC approval |

## Release decision

> **NOT READY — BLOCKERS REMAIN**

The Core persistence and NDM2 restart blockers are closed for the tested persistent data directory. Release Candidate approval remains blocked by three current, unambiguous items: the real network interruption/retry/integrity flow has not been executed; Browser handoff is disconnected and unpaired; and yt-dlp probe currently times out despite FFmpeg availability. These require a working external transfer source and a paired browser extension/media-access environment before the final RC decision can become positive.
