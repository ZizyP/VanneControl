#!/usr/bin/env python3
"""
Binary Protocol Device Client - FIXED VERSION
Timestamps in MILLISECONDS, proper CRC calculation
"""
import paho.mqtt.client as mqtt
import struct
import uuid
import time

BROKER = "localhost"
PORT = 1883
DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000"

class BinaryProtocolClient:
    MSG_PISTON_STATE = 0x01
    MSG_STATUS_UPDATE = 0x02
    MSG_TELEMETRY = 0x03
    MSG_ERROR = 0x04
    
    def __init__(self, device_id_str):
        self.device_id = uuid.UUID(device_id_str)
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, device_id_str)
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
    
    def on_connect(self, client, userdata, flags, rc):
        print(f"✅ Connected to MQTT broker (rc={rc})")
        client.subscribe(f"devices/{self.device_id}/commands/binary")
    
    def on_message(self, client, userdata, msg):
        print(f"📥 Command received")
    
    def connect(self):
        self.client.connect(BROKER, PORT, 60)
        self.client.loop_start()
        time.sleep(1)
    
    def disconnect(self):
        self.client.loop_stop()
        self.client.disconnect()
    
    def send_piston_state(self, piston_number: int, is_active: bool):
        # CRITICAL FIX: Use MILLISECONDS not seconds!
        timestamp_ms = int(time.time() * 1000)
        
        payload = struct.pack('<BBQ', piston_number, 1 if is_active else 0, timestamp_ms)
        message = self._create_message(self.MSG_PISTON_STATE, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        state = "ACTIVE" if is_active else "INACTIVE"
        print(f"🔵 Sending piston state: #{piston_number} -> {state}")
        print(f"   ✓ Sent {len(message)} bytes")
    
    def send_status_update(self, status: str, battery_level: int = None, signal_strength: int = None):
        status_code = {'offline': 0, 'online': 1, 'error': 2}.get(status.lower(), 1)
        battery = battery_level if battery_level is not None else 255
        signal = signal_strength if signal_strength is not None else 255
        
        payload = struct.pack('<BBB', status_code, battery, signal)
        message = self._create_message(self.MSG_STATUS_UPDATE, payload)
        
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔵 Sending status: {status}, Battery: {battery_level}%, Signal: {signal_strength}%")
    
    def send_telemetry(self, sensor_type: str, value: float):
        sensor_code = {'temperature': 0, 'pressure': 1, 'humidity': 2, 'voltage': 3}.get(sensor_type.lower(), 0)
        timestamp_ms = int(time.time() * 1000)
        
        payload = struct.pack('<BfQ', sensor_code, value, timestamp_ms)
        message = self._create_message(self.MSG_TELEMETRY, payload)
        
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔵 Sending telemetry: {sensor_type} = {value}")
    
    def send_error(self, error_code: int, error_message: str):
        message_bytes = error_message.encode('utf-8')
        payload = struct.pack('<I', error_code) + message_bytes
        message = self._create_message(self.MSG_ERROR, payload)
        
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔴 Sending error: Code {error_code} - {error_message}")
    
    def _create_message(self, message_type: int, payload: bytes) -> bytes:
        header = struct.pack('B', message_type)
        device_id_bytes = self.device_id.bytes
        data = header + device_id_bytes + payload
        checksum = self._calculate_crc16(data)
        return data + struct.pack('<H', checksum)
    
    def _calculate_crc16(self, data: bytes) -> int:
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8005
                else:
                    crc >>= 1
        return crc & 0xFFFF

def main():
    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║     🔧 Binary Protocol Device Simulator (FIXED)         ║")
    print("╚══════════════════════════════════════════════════════════╝\n")
    
    client = BinaryProtocolClient(DEVICE_ID)
    
    try:
        client.connect()
        
        print("="*60)
        print("DEMO SEQUENCE")
        print("="*60 + "\n")
        
        # Sequence
        client.send_status_update("online", battery_level=95, signal_strength=85)
        time.sleep(3)
        
        client.send_piston_state(3, True)
        time.sleep(3)
        
        client.send_telemetry("temperature", 23.5)
        time.sleep(2)
        
        client.send_telemetry("humidity", 65.2)
        time.sleep(2)
        
        client.send_piston_state(3, False)
        time.sleep(3)
        
        for piston in [1, 2, 4, 5]:
            client.send_piston_state(piston, True)
            time.sleep(1)
        
        time.sleep(2)
        
        client.send_telemetry("voltage", 12.3)
        time.sleep(2)
        
        client.send_telemetry("pressure", 1013.25)
        time.sleep(3)
        
        client.send_error(503, "Piston 7 sensor malfunction")
        time.sleep(3)
        
        for piston in [1, 2, 4, 5]:
            client.send_piston_state(piston, False)
            time.sleep(1)
        
        client.send_status_update("online", battery_level=92, signal_strength=80)
        
        print("\n" + "="*60)
        print("DEMO COMPLETE - Press Ctrl+C to exit")
        print("="*60 + "\n")
        
        while True:
            time.sleep(10)
            client.send_status_update("online", battery_level=90, signal_strength=75)
            
    except KeyboardInterrupt:
        print("\n⚠️  Interrupted by user")
    finally:
        client.disconnect()
        print("✅ Clean shutdown")

if __name__ == "__main__":
    main()
