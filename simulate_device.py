#!/usr/bin/env python3
"""
Simulates a Raspberry Pi device with 8 pistons
Updated to use database device ID: 7468b0d5-edf9-41a9-bdf7-2a81911b88cb
"""
import paho.mqtt.client as mqtt
import json
import time
import sys

# IMPORTANT: This must match the device ID in your database!
DEVICE_ID = "7468b0d5-edf9-41a9-bdf7-2a81911b88cb"
BROKER = "localhost"
PORT = 1883

class SimulatedDevice:
    def __init__(self):
        self.device_id = DEVICE_ID
        self.pistons = {i: "inactive" for i in range(1, 9)}
        
        print(f"🤖 Simulated Device")
        print(f"   Device ID: {self.device_id}")
        print(f"   Broker: {BROKER}:{PORT}")
        print()
        
        # Updated for paho-mqtt v2.0+
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, self.device_id)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
    
    def on_connect(self, client, userdata, flags, rc):
        print(f"✅ Device {self.device_id[:8]}... connected! (rc={rc})")
        client.subscribe(f"devices/{self.device_id}/commands")
        print(f"📡 Subscribed to: devices/{self.device_id[:8]}.../commands")
        self.publish_status()
    
    def on_message(self, client, userdata, msg):
        print(f"\n📥 Command received on {msg.topic}")
        print(f"   Payload: {msg.payload.decode()}")
        try:
            cmd = json.loads(msg.payload.decode())
            action = cmd.get("action")
            piston_num = cmd.get("piston_number")
            
            if action == "activate":
                self.activate_piston(piston_num)
            elif action == "deactivate":
                self.deactivate_piston(piston_num)
            else:
                print(f"   ⚠️  Unknown action: {action}")
        except Exception as e:
            print(f"   ❌ Error: {e}")
    
    def activate_piston(self, num):
        self.pistons[num] = "active"
        print(f"   🔧 Piston #{num} ACTIVATED")
        self.publish_telemetry(num, "activated")
        self.publish_status()
    
    def deactivate_piston(self, num):
        self.pistons[num] = "inactive"
        print(f"   🔧 Piston #{num} DEACTIVATED")
        self.publish_telemetry(num, "deactivated")
        self.publish_status()
    
    def publish_status(self):
        msg = {
            "device_id": self.device_id,
            "status": "online",
            "pistons": self.pistons,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        topic = f"devices/{self.device_id}/status"
        self.client.publish(topic, json.dumps(msg))
        
        # Show active pistons
        active = [k for k, v in self.pistons.items() if v == "active"]
        if active:
            print(f"   📤 Status published: {len(active)}/8 pistons active {active}")
        else:
            print(f"   📤 Status published: All pistons inactive")
    
    def publish_telemetry(self, piston_num, event_type):
        msg = {
            "device_id": self.device_id,
            "piston_number": piston_num,
            "event_type": event_type,
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        topic = f"devices/{self.device_id}/telemetry"
        self.client.publish(topic, json.dumps(msg))
        print(f"   📈 Telemetry published: {event_type} piston {piston_num}")
    
    def run(self):
        print(f"🚀 Starting device simulator...")
        print()
        
        try:
            self.client.connect(BROKER, PORT, 60)
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            print(f"   Make sure mosquitto is running: docker compose ps mosquitto")
            sys.exit(1)
        
        self.client.loop_start()
        
        print("💡 Simulator is running!")
        print("   Waiting for commands from API...")
        print()
        print("   To test, run in another terminal:")
        print(f"   curl -X POST http://localhost:8080/devices/{self.device_id[:8]}.../pistons/3 \\")
        print("     -H 'Authorization: Bearer $TOKEN' \\")
        print("     -H 'Content-Type: application/json' \\")
        print("     -d '{\"action\":\"activate\",\"piston_number\":3}'")
        print()
        print("Press Ctrl+C to stop\n")
        
        try:
            while True:
                time.sleep(30)
                self.publish_status()  # Heartbeat every 30 seconds
        except KeyboardInterrupt:
            print("\n🛑 Stopping device...")
            self.client.loop_stop()
            self.client.disconnect()
            print("✅ Disconnected cleanly")

if __name__ == "__main__":
    device = SimulatedDevice()
    device.run()
