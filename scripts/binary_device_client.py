#!/usr/bin/env python3
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
        print(f"✅ Connected (rc={rc})")
        client.subscribe(f"devices/{self.device_id}/commands/binary")
    
    def on_message(self, client, userdata, msg):
        pass
    
    def connect(self):
        self.client.connect(BROKER, PORT, 60)
        self.client.loop_start()
        time.sleep(1)
    
    def disconnect(self):
        self.client.loop_stop()
        self.client.disconnect()
    
    def send_piston_state(self, piston_number: int, is_active: bool):
        # CRITICAL: MILLISECONDS not seconds!
        timestamp_ms = int(time.time() * 1000)
        payload = struct.pack('<BBQ', piston_number, 1 if is_active else 0, timestamp_ms)
        message = self._create_message(self.MSG_PISTON_STATE, payload)
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔵 Piston #{piston_number} -> {'ACTIVE' if is_active else 'INACTIVE'}")
    
    def send_status_update(self, status: str, battery_level=None, signal_strength=None):
        code = {'offline': 0, 'online': 1, 'error': 2}.get(status.lower(), 1)
        battery = battery_level if battery_level else 255
        signal = signal_strength if signal_strength else 255
        payload = struct.pack('<BBB', code, battery, signal)
        message = self._create_message(self.MSG_STATUS_UPDATE, payload)
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔵 Status: {status}")
    
    def send_telemetry(self, sensor_type: str, value: float):
        code = {'temperature': 0, 'pressure': 1, 'humidity': 2, 'voltage': 3}.get(sensor_type.lower(), 0)
        timestamp_ms = int(time.time() * 1000)
        payload = struct.pack('<BfQ', code, value, timestamp_ms)
        message = self._create_message(self.MSG_TELEMETRY, payload)
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔵 Telemetry: {sensor_type} = {value}")
    
    def send_error(self, error_code: int, error_message: str):
        payload = struct.pack('<I', error_code) + error_message.encode('utf-8')
        message = self._create_message(self.MSG_ERROR, payload)
        self.client.publish(f"devices/{self.device_id}/binary", message, qos=1)
        print(f"🔴 Error {error_code}: {error_message}")
    
    def _create_message(self, message_type: int, payload: bytes) -> bytes:
        data = struct.pack('B', message_type) + self.device_id.bytes + payload
        crc = self._calculate_crc16(data)
        return data + struct.pack('<H', crc)
    
    def _calculate_crc16(self, data: bytes) -> int:
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                crc = (crc >> 1) ^ 0x8005 if crc & 1 else crc >> 1
        return crc & 0xFFFF

def main():
    print("\n🔧 Binary Protocol Device Simulator\n")
    client = BinaryProtocolClient(DEVICE_ID)
    
    try:
        client.connect()
        print("\nDEMO SEQUENCE\n" + "="*60 + "\n")
        
        client.send_status_update("online", 95, 85)
        time.sleep(3)
        
        client.send_piston_state(3, True)
        time.sleep(3)
        
        client.send_telemetry("temperature", 23.5)
        time.sleep(2)
        
        client.send_telemetry("humidity", 65.2)
        time.sleep(2)
        
        client.send_piston_state(3, False)
        time.sleep(3)
        
        for p in [1, 2, 4, 5]:
            client.send_piston_state(p, True)
            time.sleep(1)
        
        time.sleep(2)
        client.send_telemetry("voltage", 12.3)
        time.sleep(2)
        client.send_telemetry("pressure", 1013.25)
        time.sleep(3)
        
        client.send_error(503, "Piston 7 sensor malfunction")
        time.sleep(3)
        
        for p in [1, 2, 4, 5]:
            client.send_piston_state(p, False)
            time.sleep(1)
        
        client.send_status_update("online", 92, 80)
        
        print("\n" + "="*60)
        print("DEMO COMPLETE - Press Ctrl+C to exit")
        print("="*60 + "\n")
        
        while True:
            time.sleep(10)
            client.send_status_update("online", 90, 75)
            
    except KeyboardInterrupt:
        print("\n⚠️  Stopped")
    finally:
        client.disconnect()
        print("✅ Shutdown complete")

if __name__ == "__main__":
    main()
