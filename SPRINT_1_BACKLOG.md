# WattWatch — Sprint 1 Backlog

**Interdisciplinary Project | First implementation deliverable | 26 November 2026**

## Sprint goal
Deliver a working Flutter web prototype that displays live power and on/off states for five simulated household appliances, calculates total power, and allows remote switching through MQTT.

This is a reconstructed sprint backlog for the review; the team should confirm original sprint scope, owners and priorities. “Demonstrated” means basic functionality was observed or reported working, not that every formal acceptance criterion passed. H = high, M = medium (proposed priorities).

## User stories

| ID | User story | Reference / acceptance check | Priority | Status | Owner |
|---|---|---|---|---|---|
| US-01 | As a user, I want to see live appliance power so I can understand consumption. | FR-02 / AC-05: show watts and update without refresh. | H | Demonstrated | Ana Carjila (web UI) |
| US-02 | As a user, I want to see on/off status so I know which appliances are active. | FR-02 / AC-05: display received state. | H | Demonstrated; offline behavior pending | Ana Carjila (web UI) |
| US-03 | As a user, I want to see total household power so I can monitor overall demand. | FR-02 / AC-06: sum watts of on devices. | H | Demonstrated; independent sum check pending | Ana Carjila (web UI) |
| US-04 | As a user, I want to switch appliances remotely so I can control consumption. | FR-03 / AC-10–12: send command, confirm state, show 0 W when off; timeout feedback. | H | Normal control demonstrated; timeout and timing tests pending | Ana Carjila (web UI) |

## Technical tasks

| ID | Task / completion check | Priority | Status | Owner |
|---|---|---|---|---|
| T-01 | Initialize repository and Flutter project. | H | Done | Team — confirm |
| T-02 | Implement Python simulator with five appliance profiles and 2 s publication interval (AC-37). | H | Demonstrated | Confirm |
| T-03 | Connect simulator and browser to HiveMQ; receive power/status JSON (AC-05). | H | Demonstrated | Team / Ana (web) |
| T-04 | Implement dashboard, state mapping and power aggregation (AC-05–06). | H | Demonstrated | Ana Carjila |
| T-05 | Publish commands with UUIDs and process matching acknowledgments (AC-39–40). | H | Normal path demonstrated | Team / Ana (web) |
| T-06 | Implement 5 s command timeout and failure message (AC-12). | H | Implemented; test pending | Ana Carjila |
| T-07 | Supply Home ID at launch using --dart-define; no fixed household ID in source. | H | Demonstrated | Ana Carjila |
| T-08 | Publish web implementation on feature/web-dashboard and open PR #3. | H | Done; review pending | Ana Carjila |
| T-09 | Document launch procedure and MQTT topic contract. | H | Draft prepared; add to repository | Confirm |
| T-10 | Record smoke-test evidence; verify all five devices, total and command round trip. | H | In progress | Team — confirm |
| T-11 | Review overlapping native and web implementations before merging. | M | Open | Team — confirm |

## Open technical issues and next steps

| Issue | Reference | Action |
|---|---|---|
| Device offline detection / stale values | AC-07, AC-13 | Detect missing readings while broker is connected; preserve last known reading. |
| Broker reconnect and restored banner | AC-08–09, AC-43 | Implement and test automatic recovery in web version. |
| Command error responses and timeout recovery | Clarified AC-12 | Support error result/reason; test missing ACK and resynchronize. |
| Realistic usage schedules and configuration | AC-38, EC-02 | Document five profiles; improve schedules and configurable simulator. |
| Public unauthenticated broker and plain transport | FR-08, C-04 | Development only; no personal data; implement private TLS broker and access controls. |
| Default Flutter counter test | Testing strategy | Replace obsolete widget test; add unit and integration tests. |
| Formal latency and load tests | NFR-01, NFR-04 | Measure reading/command delays; later test 50 concurrent users. |
| Authentication, persistent device management, history, cost, alerts and quarantine | FR-01, FR-04–09 | Future increments; not claimed as complete in web sprint. |

## Evidence and sprint review
- Simulator log: connection to HiveMQ and publication for five devices every 2 seconds.
- Chrome screenshot: live readings, 281.8 W total and 3 of 5 active devices; configurable Home ID launch demonstrated.
- Normal remote switching reported successful before final Home ID change; repeat on final branch and capture command ACK logs.
- GitHub: https://github.com/AnaCarjil/watt-watch/pull/3 — open PR from feature/web-dashboard to main, one commit at creation. Existing native branch live-dashboard-control preserved.
- Sprint review and retrospective: to be conducted with the professor in the lab. No feedback or formal acceptance results are claimed in advance.

Sources: WattWatch Technical Specification v1.0 (15 October 2026), clarification answers, Technical Offer, simulator source, student-provided runtime screenshots and GitHub PR screenshot (26 November 2026).
