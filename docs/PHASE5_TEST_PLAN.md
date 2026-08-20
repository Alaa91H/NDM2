# NDM2 Phase 5 — Release Candidate Hardening Plan

## Objective

Phase 5 hardens the existing native NDM2 client for a controlled Release Candidate. The work is constrained to reliability, recovery, security, performance observation, reproducible packaging, and regression prevention. The NOVA Rust Core remains authoritative; no competing engine, listener, authentication scheme, or legacy-front-end change is permitted.

## Release blocker rule

A finding is a **Blocker** when it prevents a safe release, including a crash, state loss or corruption, protected-route authentication bypass, token exposure, broken real download flow, unrecoverable daemon recovery failure, corrupted install artifact, or Release build failure. A **High** finding must be fixed before the Release Candidate or explicitly accepted with specific rationale. Medium and Low findings can be deferred only when they do not compromise the release decision.

| Workstream | Required evidence | Classification if unsuccessful |
|---|---|---|
| Native and Core regression | Clean Debug/Release builds, CTest, Rust library tests | Blocker |
| Daemon recovery | Live disconnect, offline state, reconnect, reconciliation | Blocker |
| Real transfers | Creation, interruption/recovery where practical, file result and state | Blocker |
| Application restart | Active/completed/queued state reconciliation without duplication | Blocker |
| Security boundary | Loopback listener, protected endpoint rejection, invalid token, secret scan | Blocker |
| Settings and locale | Persistence across restart, LTR/RTL behavior | High |
| Packaging | Clean install outside build directory with no developer paths | Blocker |
| Browser and media regression | Existing real route where environment supports it | High |
| Performance and soak | Actual observations with environment and task scale stated | High, unless a release blocker is found |

## Executable validation sequence

The phase will first inspect the current client, build rules, tests, and package dependencies. Native tests will be expanded only where they can exercise real model, settings, adapter parsing, or failure behavior without converting the product into a mock-only test suite. The live daemon will then be used for disconnect/reconnect, restart, authenticated download, invalid-input, and safe cleanup scenarios.

A sustained observation session will be run only for the duration actually available in this environment. Task counts, renderer, desktop session, and the distinction between real Core data and explicitly labeled stress data will be recorded. No 1000-task or multi-platform claim will be inferred without direct evidence.

## Platform and environment scope

| Platform | Build | Launch | Core connection | Real download | Browser | Packaging |
|---|---|---|---|---|---|---|
| Linux / Ubuntu / Qt 6.4.2 | Planned in this phase | Planned | Planned | Planned | Planned where bridge is available | Planned |
| Windows | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested |
| macOS | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested |

System tray is explicitly out of scope for this Release Candidate because it is not implemented and is not established as a release requirement. Arabic translation resources are also not fabricated; the phase will validate translation readiness, locale persistence, and RTL layout only.

## Acceptance decision

The final report will use exactly one of these outcomes:

> **READY FOR RELEASE CANDIDATE**

> **NOT READY — BLOCKERS REMAIN**

The first outcome requires every executed release-critical test to pass and every unavailable coverage area to be explicitly stated rather than inferred.
