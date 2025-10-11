#!/usr/bin/env python3
"""Simulates a Raspberry Pi device with 8 pistons"""
import paho.mqtt.client as mqtt
import json
import time

DEVICE_ID = "raspberry-pi-001"
BROKER = "localhost"
PORT = 1883

class SimulatedDevice:
    def __init__(self):
        self.device_id = DEVICE_ID
        self.pistons = {i: "inactive" for i in range(1, 9)}
        
        # Updated for paho-mqtt v2.0+
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, self.device_id)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
    
    def on_connect(self, client, userdata, flags, rc):
        print(f"✅ Device {self.device_id} connected! (rc={rc})")
        client.subscribe(f"devices/{self.device_id}/commands")
        self.publish_status()
    
    def on_message(self, client, userdata, msg):
        print(f"\n📥 Command received: {msg.payload.decode()}")
        try:
            cmd = json.loads(msg.payload.decode())
            action = cmd.get("action")
            piston_num = cmd.get("piston_number")
            
            if action == "activate":
                self.activate_piston(piston_num)
            elif action == "deactivate":
                self.deactivate_piston(piston_num)
        except Exception as e:
            print(f"❌ Error: {e}")
    
    def activate_piston(self, num):
        self.pistons[num] = "active"
        print(f"🔧 Piston #{num} ACTIVATED")
        self.publish_telemetry(num, "activated")
        self.publish_status()
    
    def deactivate_piston(self, num):
        self.pistons[num] = "inactive"
        print(f"🔧 Piston #{num} DEACTIVATED")
        self.publish_telemetry(num, "deactivated")
        self.publish_status()
    
    def publish_status(self):
        msg = {
            "device_id": self.device_id,
            "status": "online",
            "pistons": self.pistons,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        self.client.publish(f"devices/{self.device_id}/status", json.dumps(msg))
        print(f"📤 Status published")
    
    def publish_telemetry(self, piston_num, event_type):
        msg = {
            "device_id": self.device_id,
            "piston_number": piston_num,
            "event_type": event_type,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        self.client.publish(f"devices/{self.device_id}/telemetry", json.dumps(msg))
    
    def run(self):
        print(f"🚀 Starting {self.device_id}...")
        self.client.connect(BROKER, PORT, 60)
        self.client.loop_start()
        
        print("\n💡 Device running. Send commands like this:")
        print(f'   docker-compose exec mosquitto mosquitto_pub -t "devices/{self.device_id}/commands" -m \'{{"action":"activate","piston_number":3}}\'')
        print("\nPress Ctrl+C to stop\n")
        
        try:
            while True:
                time.sleep(30)
                self.publish_status()
        except KeyboardInterrupt:
            print("\n🛑 Stopping device...")
            self.client.loop_stop()
            self.client.disconnect()

if __name__ == "__main__":
    device = SimulatedDevice()
    device.run()
