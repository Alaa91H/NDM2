# Phase 5.1 — Current Recovery Findings

## Persistent daemon state

The current NOVA integration daemon stores state beneath `HOME/nova-download-manager`, using `downloads-state.json`. The Core persistence code restores its snapshot on daemon startup; direct HTTP(S) jobs that were running are intentionally restored in a paused state. This behavior is defined in the existing Core implementation and was not modified.

Three real Core tasks were created through the authenticated `/api/downloads` contract: a completed 1 MiB task, a rate-limited active 10 MiB task, and a queued 1 MiB task. Before daemon restart, the tasks had distinct stable UUIDs. The durable state file contained all three tasks. After a graceful daemon restart using the same persistent data directory, the API returned all three original IDs: the completed task remained completed and active/queued work returned paused, which is the existing Core restart semantic. Evidence is stored under `docs/evidence/phase51/` in structured JSON snapshots.

| Test | Result |
|---|---|
| Durable state file created | Pass |
| Completed task retained | Pass |
| Active task retained | Pass; restored paused by Core semantics |
| Queued task retained | Pass; restored paused by Core semantics |
| Stable Core IDs after daemon restart | Pass: 3/3 |
| Client-side task recreation | Not performed |

## NDM2 restart recovery

With the persistent daemon active, normal NDM2 shutdown and restart retained the Core collection. The restarted client reconciled exactly three Core-backed rows and did not create duplicates. An abnormal `SIGKILL` termination of NDM2 was also followed by a normal restart; structured snapshots recorded the same three task IDs before, during, and after the client restart. The client again rendered exactly three rows.

The active task later entered the Core `error` state with the existing Core message that no data had been received for 60 seconds. This is a real transfer failure from the remote source path and is not attributed to NDM2 termination. The client represented it accurately with a visible error message and did not lose or duplicate its task record.

| Test | Result |
|---|---|
| Normal NDM2 restart | Pass: three stable Core IDs and three reconciled rows |
| Abnormal NDM2 termination | Pass: three stable Core IDs and three reconciled rows |
| UI representation of task failure | Pass: real Core error displayed |
| Active transfer continuity | Not passed in this run; Core task stalled at the remote source |
