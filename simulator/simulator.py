import json
import time
import uuid
import random
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

BROKER = "broker.hivemq.com"
PORT = 1883
HOME_ID = str(uuid.uuid4())

DEVICES = {
    "dev-fridge-01": {"name": "Fridge", "type": "fridge", "state": "on", "base_watts": 120.0},
    "dev-kettle-02": {"name": "Kettle", "type": "kettle", "state": "off", "base_watts": 2000.0},
    "dev-tv-03": {"name": "Living Room TV", "type": "tv", "state": "on", "base_watts": 95.0},
    "dev-washer-04": {"name": "Washing Machine", "type": "washer", "state": "off", "base_watts": 500.0},
    "dev-laptop-05": {"name": "Laptop Charger", "type": "charger", "state": "on", "base_watts": 65.0},
}

def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def on_connect(client, userdata, flags, reason_code, properties=None):
    print(f"\n[CONNECTED] Broker: {BROKER}")
    print(f"[HOME ID]   {HOME_ID}")
    print("-" * 60)
    for dev_id, info in DEVICES.items():
        print(f"  Device ID: {dev_id} | {info['name']} ({info['state']})")
        client.subscribe(f"wattwatch/{HOME_ID}/{dev_id}/cmd")
        client.publish(
            f"wattwatch/{HOME_ID}/{dev_id}/status",
            json.dumps({"ts": now_iso(), "state": info["state"]}),
            retain=True,
        )
    print("-" * 60)

def on_message(client, userdata, msg):
    parts = msg.topic.split("/")
    if len(parts) == 4 and parts[3] == "cmd":
        dev_id = parts[2]
        if dev_id not in DEVICES:
            return
        payload = json.loads(msg.payload.decode())
        cmd_id = payload.get("cmdId")
        action = payload.get("action")
        if action in ("on", "off"):
            DEVICES[dev_id]["state"] = action
            ts = now_iso()
            client.publish(
                f"wattwatch/{HOME_ID}/{dev_id}/status",
                json.dumps({"ts": ts, "state": action}),
                retain=True,
            )
            client.publish(
                f"wattwatch/{HOME_ID}/{dev_id}/ack",
                json.dumps({"cmdId": cmd_id, "state": action, "ts": ts}),
            )
            print(f"[CMD ACK] {dev_id} -> {action.upper()} (cmdId={cmd_id})")

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(BROKER, PORT, 60)
client.loop_start()

try:
    tick = 0
    while True:
        tick += 1
        for dev_id, info in DEVICES.items():
            if info["state"] == "off":
                watts = 0.0
            elif info["type"] == "fridge":
                watts = 120.0 + random.uniform(-3, 3) if (tick // 5) % 2 == 0 else 5.0
            else:
                watts = info["base_watts"] + random.uniform(-2.5, 2.5)
            watts = round(max(0.0, watts), 1)
            client.publish(
                f"wattwatch/{HOME_ID}/{dev_id}/power",
                json.dumps({"ts": now_iso(), "watts": watts}),
            )
        print(f"[{now_iso()}] Published readings for {len(DEVICES)} devices.")
        time.sleep(2)
except KeyboardInterrupt:
    for dev_id in DEVICES:
        client.publish(
            f"wattwatch/{HOME_ID}/{dev_id}/status",
            json.dumps({"ts": now_iso(), "state": "offline"}),
            retain=True,
        )
    client.loop_stop()
    client.disconnect()
