# WattWatch — Sprint 1 web quickstart

This increment targets Google Chrome. Native macOS work is preserved separately on `live-dashboard-control`. The web version is on `feature/web-dashboard` (PR #3), not necessarily on `main`.

## Requirements
Python 3, Flutter SDK compatible with mobile_app/pubspec.yaml, Git, Google Chrome, and internet access to the public HiveMQ MQTT broker.

## Get the code
```bash
git clone -b feature/web-dashboard https://github.com/AnaCarjil/watt-watch.git
cd watt-watch
```
For an existing clone, fetch and switch to the web branch instead.

## Terminal 1 — simulator (macOS/Linux)
```bash
cd simulator
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
python3 simulator.py
```
Wait for `[CONNECTED]` and copy the `[HOME ID]` UUID. Keep the simulator running.

## Terminal 2 — Flutter (from repository root)
```bash
cd mobile_app
flutter pub get
flutter run -d chrome --dart-define=HOME_ID=YOUR_HOME_ID
```
Replace YOUR_HOME_ID with the current simulator UUID. A simulator restart generates a new ID; relaunch Flutter with that ID. Do not use real household data or credentials.

## Smoke test
1. Verify Connected to MQTT and readings for five appliances.
2. Observe automatic updates and check the total equals the sum of on-device readings (allow for asynchronous updates).
3. Turn the kettle on and off; verify approximately 2000 W when on and 0 W when off.
4. Repeat for the TV and check `[CMD ACK]` in the simulator terminal.
5. Stop both processes using Ctrl+C.

## MQTT contract (current implementation)
Prefix: `wattwatch/<homeId>/<deviceId>/`. Python uses TCP port 1883; Chrome uses `ws://broker.hivemq.com/mqtt` on port 8000. All payloads are JSON. This is a development broker, not secure production infrastructure.

| Suffix | Direction | Payload fields | Notes |
|---|---|---|---|
| power | Simulator → app | ts, watts | Every 2 s; 0 W when off |
| status | Simulator → app | ts, state | Retained; on/off/offline |
| cmd | App → simulator | cmdId, action | Unique command ID; on/off; not retained |
| ack | Simulator → app | cmdId, state, ts | Successful execution confirmation |

## Current simulated profiles
| Device ID | Nominal power | Current behavior |
|---|---|---|
| dev-fridge-01 | 120 W | Cycles between about 120 W and 5 W while on |
| dev-kettle-02 | 2000 W | On/off controlled; small random variation when on |
| dev-tv-03 | 95 W | On/off controlled; small random variation when on |
| dev-washer-04 | 500 W | On/off controlled; small random variation when on |
| dev-laptop-05 | 65 W | On/off controlled; small random variation when on |

These are implemented profiles, not a complete realistic usage-schedule specification. Explicit error acknowledgments, offline watchdog, automatic reconnection, Firebase, historical data, cost, alerts, and formal acceptance tests remain unfinished in the web increment. The original counter widget test needs replacement.
