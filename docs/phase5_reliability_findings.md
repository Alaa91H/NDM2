# Phase 5 — Reliability Findings Log

## Daemon interruption and restart

| Finding | Severity | Evidence | Current status |
|---|---|---|---|
| The client still rendered `Core connected` four seconds after the real NOVA daemon process was terminated. | High pending timing confirmation | `docs/phase5_daemon_offline.png` | Needs a longer observation and adapter-timer review. |
| After the daemon was restarted successfully and its authenticated `/api/downloads` endpoint returned HTTP 200, the client reconciled to `0 visible of 0 tasks` although it had shown four tasks before the daemon restart. | **Blocker pending Core persistence confirmation** | `docs/phase5_daemon_reconnected.png` | The integration daemon restarted with no prior task history. No client-side state was fabricated or restored. This prevents a Release Candidate pass for daemon-restart recovery unless the production daemon's persistence contract differs and is directly demonstrated. |

The test did not crash the NDM2 client and it did not duplicate stale tasks. It did, however, expose that the tested daemon restart did not restore the prior task history. The Core is authoritative; no Phase 5 UI change will attempt to preserve or re-create tasks locally.

## SSE Offline correction re-test

| Finding | Severity | Evidence | Current status |
|---|---|---|---|
| A real daemon termination now produces a clear `Waiting for NOVA Core` state, `Core offline` badge, and reconnect message within two seconds. | Fixed High | `docs/evidence/phase5/phase5_daemon_offline_fixed.png` | The client-side SSE error path now sets `connected` false. |
| Three seconds after an authenticated daemon restart, the UI was still offline. | High pending recovery-window confirmation | `docs/evidence/phase5/phase5_daemon_reconnected_fixed.png` | The refresh timer is configured at ten seconds, so recovery must be checked after the real timer window before classification. |

The daemon restart in integration mode still began with an empty authoritative task collection. The client did not resurrect stale rows, which is correct; persistence of the daemon task history remains a separate Core/environment contract issue.

## Recovery-window result

`docs/evidence/phase5/phase5_daemon_recovered_after_refresh.png` confirms that after the configured ten-second refresh window the client returned to `Core connected` and presented the authoritative empty collection without a crash, duplicate row, stale task resurrection, or frozen UI. The transient three-second offline period is therefore not a persistent reconnect failure. The integration daemon's lack of retained task history across process restart remains a deployment/persistence limitation that must be a blocker unless the Release Candidate is explicitly coupled to a persistent production daemon configuration.
