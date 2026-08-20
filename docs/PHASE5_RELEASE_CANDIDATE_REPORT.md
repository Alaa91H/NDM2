# NDM2 Phase 5 — Release Candidate Hardening Report

**Candidate version:** NDM2 `3.0.0`

**Native stack:** C++20 / Qt 6.4.2 / Qt Quick

**Core architecture:** Existing NOVA Rust daemon, authenticated loopback HTTP/SSE

**Decision:** **NOT READY — BLOCKERS REMAIN**

## Scope and production-hardening changes

Phase 5 did not redesign the client and did not modify the NOVA Rust Core or the preserved React/Tauri frontend. The work hardened the native client around demonstrable release risks. The SSE failure handler now immediately changes the client connection state to Offline when the live event stream ends with an error. This prevents the previous misleading `Core connected` presentation during a real daemon outage. Settings now normalize unsupported persisted theme, density, and locale values to safe defaults, sync changes immediately, and are covered by a real isolated-QSettings test. The native application now takes its version directly from CMake's project version and publishes it to Diagnostics as `NDM2 3.0.0`.

A Linux release-packaging script was added. It bundles the release executable, required Qt runtime libraries, XCB platform plugin, image plugins, and the Qt Quick QML modules needed by the application. It produces a deterministic `.tar.gz` archive when `SOURCE_DATE_EPOCH` is fixed and supplies a launcher that sets only bundle-relative runtime paths. The bundle deliberately does not include a daemon bearer credential; the NOVA daemon remains a separately managed authenticated loopback service.

| Area | Result |
|---|---|
| SSE disconnect indication | Fixed and verified on a real X11 desktop. |
| Reconnect behavior | Verified after the client's configured 10-second refresh cycle. |
| Settings persistence and malformed preference safety | Added to native test suite and passed. |
| Client version information | CMake `3.0.0` is exposed to Qt and Diagnostics. |
| Linux packaging | Reproducible bundle and clean-path launch passed. |
| Core or legacy frontend changes | None. |

## Reliability evidence

A real NOVA daemon process was terminated while NDM2 was running. Before the fix, the client continued to display `Core connected` after four seconds. After the fix, the real desktop displayed `Waiting for NOVA Core`, `Core offline`, and `Live update stream reconnecting` within two seconds. After the daemon returned and the client completed its configured refresh interval, the client returned to `Core connected` without a crash, duplicate row, UI freeze, or stale-row resurrection.

The daemon restarted successfully and its protected download endpoint returned HTTP 200 with valid credentials. However, the integration daemon came back with an empty authoritative task collection. NDM2 correctly reconciled to that empty collection rather than recreating the four previous rows locally. This is correct client behavior, but it does not satisfy the required release proof that real daemon task state persists across a daemon restart.

| Scenario | Actual outcome | Classification |
|---|---|---|
| SSE stream loss | Clear Offline state within two seconds after client fix. | Fixed High |
| Daemon reconnect | Connection recovered after refresh cycle; no client crash or stale resurrection. | Pass |
| Daemon restart state | Integration daemon restarted with zero task history. | **Blocker: persistence contract not demonstrated** |
| NDM2 restart with completed deletion | Passed previously in Phase 4.1; deleted task did not return. | Historical evidence only |
| Active/queued restart and abnormal termination | Not executed in Phase 5. | Blocker verification gap |
| Real network interruption and Core retry recovery | Not executed in this environment. | Blocker verification gap |

The detailed desktop evidence is retained in `docs/evidence/phase5/phase5_daemon_offline_fixed.png`, `docs/evidence/phase5/phase5_daemon_reconnected_fixed.png`, `docs/evidence/phase5/phase5_daemon_recovered_after_refresh.png`, and `docs/phase5_reliability_findings.md`.

## Stability and performance observation

A 30-minute monitoring session observed the active NDM2 client and NOVA daemon at 15-second intervals while the protected `/api/downloads` endpoint was polled. The session recorded 120 samples. The final stored sample was at 1,789 seconds because the 15-second cadence crossed the 1,800-second boundary before a further row was due; the monitor itself was configured for 1,800 seconds.

| Observation | Measured value |
|---|---:|
| NDM2 RSS range | 117,936–124,648 KiB |
| NDM2 final RSS | 122,732 KiB |
| NOVA RSS range | 44,012–51,100 KiB |
| NOVA final RSS | 51,100 KiB |
| Client CPU near final samples | 0.5% |
| Daemon CPU near final samples | 0.7% |
| Protected health samples other than HTTP 200 | 0 / 120 |
| Renderer and desktop | Mesa llvmpipe software rendering; X11/Openbox |
| Task-library scale | Empty authoritative collection after integration-daemon restart |

These are actual environment observations, not a hardware-GPU performance claim and not a large-library benchmark. No 100/500/1000-row claim is made. The raw sampling data and monitor are retained in `docs/phase5_soak_metrics.csv` and `scripts/phase5_soak_monitor.sh`.

## Security review

The daemon listener was confirmed on `127.0.0.1:3199`. The protected `/api/downloads` route returned HTTP 401 for an invalid Bearer credential and HTTP 200 for the active integration credential. The public health route is not presented as evidence for access to protected operations. The native adapter continues to reject non-loopback daemon endpoints and sends the credential only through its existing request path.

A scan of Phase 5 documentation, scripts, and release bundle text found no bearer credential, test token, API key, or developer home path. The generated archive likewise contains no test token. Diagnostics continues to redact Bearer values and token-like fields before displaying logs. No new network listener or browser-facing service was added.

| Control | Result |
|---|---|
| Protected route with invalid credential | Pass: HTTP 401 |
| Protected route with valid credential | Pass: HTTP 200 |
| Listener scope | Pass: loopback only |
| Test token in Phase 5 files or release bundle | Pass: absent |
| Developer path in release text files | Pass: absent |
| Diagnostics token redaction | Existing implementation retained |

## Native tests and reproducible packaging

The clean Debug build passed and `NDM2ModelTests` passed 1/1. The test suite now covers filtering, sorting, incremental delta removal, and persisted settings normalization for theme, density, locale, RTL state, and notification preferences. The Core library suite passed 712/712 tests. The Core suite emitted its existing warning that this environment uses fallback/system libcurl; it did not report a test failure.

The clean Release build passed. Two consecutive package builds with `SOURCE_DATE_EPOCH=0` produced the same archive digest:

> `3beab0063536a73a13e452756935f653821d9b65e8889ca0a697f8034139e272`

The archive was extracted under `/tmp`, then started through its own launcher while `build-release` was temporarily absent and the environment had isolated HOME/XDG paths. It remained healthy for the expected eight-second timeout without missing-library, missing-QML-module, or missing-Qt-platform-plugin errors. This is a clean-path launch test, not a claim of fresh OS virtual-machine coverage.

| Validation | Result |
|---|---|
| Clean Debug build | Pass |
| `ctest --test-dir build --output-on-failure` | Pass: 1/1 |
| Clean Release build | Pass |
| Deterministic package rebuild | Pass |
| Extracted package launch outside build directory | Pass |
| Rust Core library tests | Pass: 712/712 |
| Windows and macOS build/package | Not tested |
| Fresh OS/VM installation | Not tested |
| Upgrade/uninstall policy execution | Not tested |

## Browser, media, notification, localization, and tray status

The existing browser handoff and real media workflow were verified in the prior Phase 3.5 work, but they were not re-run in this Phase 5 session after the integration daemon reset. They are therefore not presented as Phase 5 regression passes. System-tray and notification code are present in the native application, but the Openbox session did not provide a supported tray host for an end-to-end desktop notification acceptance claim. RTL layout and locale persistence were previously validated; no artificial Arabic translation catalogue was created.

## Release blocker review

| Finding | Severity | Reproducible | Fixed | Release blocking |
|---|---|---:|---:|---:|
| SSE failure left UI connected | High | Yes | Yes | No |
| Integration daemon restart lost prior task collection | Blocker | Yes in integration mode | No; Core/environment persistence contract | Yes |
| Active/queued task restart and abnormal-NDM2-termination recovery not revalidated | Blocker verification gap | Not executed | No | Yes |
| Real network-interruption retry and final file-integrity recovery not revalidated | Blocker verification gap | Not executed | No | Yes |
| Browser handoff regression not re-run in Phase 5 | High verification gap | Not executed | No | Yes for requested RC acceptance |
| Media probe/download regression not re-run in Phase 5 | High verification gap | Not executed | No | Yes for requested RC acceptance |
| Linux clean-path package runtime | High | Yes | Yes | No |
| Windows/macOS packaging | Medium coverage gap | Not available | No | No for Linux-only controlled deployment |

> **Release decision: NOT READY — BLOCKERS REMAIN.** The native client is materially stronger: it has real offline signaling, settings hardening, version alignment, reproducible Linux packaging, a successful clean-path launch, successful native/Core suites, and a 30-minute monitored stability session. It must not be labelled a Release Candidate yet because daemon-state persistence and the other explicitly required recovery/regression proofs have not been demonstrated. The report does not hide these gaps as cosmetic limitations.

## Required closure path

A subsequent controlled run must use the intended persistent NOVA daemon configuration, create active, queued, and completed tasks, restart both NDM2 and daemon, and demonstrate exact reconciliation without duplication or loss. It must also interrupt a real transfer at the network layer, verify Core retry/resume and output integrity, then repeat the browser and media end-to-end routes. After those blockers close, a fresh-OS installation/upgrade/uninstall test should be run for any platform being declared supported.
