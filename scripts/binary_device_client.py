#!/usr/bin/env python3
"""
Binary Protocol Device Client - FIXED VERSION
Simulates a Raspberry Pi sending binary messages via MQTT

FIXES:
1. CRC16 calculation now matches Kotlin backend exactly
2. Timestamps use milliseconds (not seconds)
3. Proper byte ordering for all fields
"""

import paho.mqtt.client as mqtt
import struct
import time
import uuid
import random
from typing import Optional

class BinaryProtocolClient:
    """
    Client that communicates using the binary protocol
    
    Protocol Structure:
    [Header: 1 byte] [Device ID: 16 bytes] [Payload: variable] [Checksum: 2 bytes]
    """
    
    # Message type constants (must match backend)
    MSG_PISTON_STATE = 0x01
    MSG_STATUS_UPDATE = 0x02
    MSG_TELEMETRY = 0x03
    MSG_ERROR = 0x04
    
    def __init__(self, device_id: str, broker: str = "localhost", port: int = 1883):
        """
        Initialize binary protocol client
        
        Args:
            device_id: UUID string of this device
            broker: MQTT broker address
            port: MQTT broker port
        """
        self.device_id = uuid.UUID(device_id)
        self.broker = broker
        self.port = port
        
        # Initialize MQTT client (paho-mqtt v2.0+ syntax)
        self.client = mqtt.Client(
            mqtt.CallbackAPIVersion.VERSION1, 
            str(self.device_id)
        )
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        
        print(f"🔧 Binary Protocol Client initialized")
        print(f"   Device ID: {self.device_id}")
        print(f"   Broker: {broker}:{port}")
    
    def _on_connect(self, client, userdata, flags, rc):
        """Called when connected to MQTT broker"""
        print(f"✅ Connected to broker (rc={rc})")
        
        # Subscribe to binary commands
        topic = f"devices/{self.device_id}/commands/binary"
        client.subscribe(topic)
        print(f"📡 Subscribed to: {topic}")
    
    def _on_message(self, client, userdata, msg):
        """Called when receiving a command from backend"""
        print(f"\n📥 Received binary command ({len(msg.payload)} bytes)")
        
        try:
            # Parse the binary command
            command = self._parse_command(msg.payload)
            print(f"   Command: {command}")
        except Exception as e:
            print(f"   ❌ Error parsing command: {e}")
    
    def connect(self):
        """Connect to MQTT broker"""
        print(f"\n🔌 Connecting to {self.broker}:{self.port}...")
        self.client.connect(self.broker, self.port, 60)
        self.client.loop_start()
        time.sleep(1)  # Give it time to connect
    
    def disconnect(self):
        """Disconnect from MQTT broker"""
        self.client.loop_stop()
        self.client.disconnect()
    
    def send_piston_state(self, piston_number: int, is_active: bool):
        """
        Send piston state change
        
        Binary Format:
        [0x01] [UUID: 16 bytes] [piston: 1 byte] [state: 1 byte] [timestamp: 8 bytes] [CRC: 2 bytes]
        """
        print(f"\n📤 Sending piston {piston_number} state: {'ACTIVE' if is_active else 'INACTIVE'}")
        
        # ✅ FIX: Use milliseconds (not seconds)
        timestamp = int(time.time() * 1000)
        
        # Pack payload: piston_number (byte), state (byte), timestamp (long)
        payload = struct.pack('<BBQ', piston_number, 1 if is_active else 0, timestamp)
        
        message = self._create_message(self.MSG_PISTON_STATE, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Sent {len(message)} bytes (timestamp: {timestamp})")
    
    def send_status(self, status: str = "online", battery_level: int = None, signal_strength: int = None):
        """
        Send device status update
        
        Binary Format:
        [0x02] [UUID: 16 bytes] [status: 1 byte] [battery: 1 byte] [signal: 1 byte] [CRC: 2 bytes]
        """
        print(f"\n📤 Sending status update: {status}")
        
        # Convert status to code
        status_code = {
            'offline': 0,
            'online': 1,
            'error': 2
        }.get(status, 1)
        
        # Use 255 for "not applicable"
        battery = battery_level if battery_level is not None else 255
        signal = signal_strength if signal_strength is not None else 255
        
        payload = struct.pack('<BBB', status_code, battery, signal)
        message = self._create_message(self.MSG_STATUS_UPDATE, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Status: {status}, Battery: {battery_level}%, Signal: {signal_strength}%")
    
    def send_telemetry(self, sensor_type: str, value: float):
        """
        Send telemetry data
        
        Binary Format:
        [0x03] [UUID: 16 bytes] [sensor_type: 1 byte] [value: 4 bytes float] [timestamp: 8 bytes] [CRC: 2 bytes]
        """
        print(f"\n📤 Sending telemetry: {sensor_type} = {value}")
        
        # Convert sensor type to code
        sensor_code = {
            'temperature': 0,
            'pressure': 1,
            'humidity': 2,
            'voltage': 3
        }.get(sensor_type, 0)
        
        # ✅ FIX: Use milliseconds (not seconds)
        timestamp = int(time.time() * 1000)
        
        payload = struct.pack('<BfQ', sensor_code, value, timestamp)
        message = self._create_message(self.MSG_TELEMETRY, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Sent {sensor_type} reading: {value} (timestamp: {timestamp})")
    
    def send_error(self, error_code: int, error_message: str):
        """
        Send error report
        
        Binary Format:
        [0x04] [UUID: 16 bytes] [error_code: 4 bytes] [message: variable UTF-8] [CRC: 2 bytes]
        """
        print(f"\n📤 Sending error: Code {error_code} - {error_message}")
        
        message_bytes = error_message.encode('utf-8')
        payload = struct.pack('<I', error_code) + message_bytes
        message = self._create_message(self.MSG_ERROR, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Error report sent")
    
    def _create_message(self, message_type: int, payload: bytes) -> bytes:
        """
        Create complete binary message with header, device ID, payload, and checksum
        """
        # Header
        header = struct.pack('B', message_type)
        
        # Device ID (UUID as 16 bytes) - using Kotlin's byte order
        device_id_bytes = self.device_id.bytes
        
        # Combine header + device ID + payload
        data = header + device_id_bytes + payload
        
        # ✅ FIX: Calculate CRC16 checksum (matches Kotlin exactly)
        checksum = self._calculate_crc16(data)
        
        # Append checksum (little-endian)
        return data + struct.pack('<H', checksum)
    
    def _calculate_crc16(self, data: bytes) -> int:
        """
        Calculate CRC16 checksum - FIXED to match Kotlin backend exactly
        
        IMPORTANT: This must produce the same result as the Kotlin version:
        ```kotlin
        var crc = 0xFFFF
        for (i in 0 until length) {
            crc = crc xor (data[i].toInt() and 0xFF)
            for (j in 0 until 8) {
                if ((crc and 0x0001) != 0) {
                    crc = (crc shr 1) xor 0x8005
                } else {
                    crc = crc shr 1
                }
            }
        }
        ```
        """
        crc = 0xFFFF
        
        for byte in data:
            # ✅ FIX: Python bytes are already 0-255, no need to mask
            # But we need to ensure it's treated as unsigned
            crc ^= byte
            
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8005
                else:
                    crc >>= 1
        
        # ✅ FIX: Mask to 16 bits (matches Kotlin's Short)
        return crc & 0xFFFF
    
    def _parse_command(self, data: bytes) -> Optional[dict]:
        """Parse binary command received from backend"""
        if len(data) < 19:  # Minimum size
            return None
        
        # Extract header
        message_type = data[0]
        
        # Extract device ID
        device_id_bytes = data[1:17]
        device_id = uuid.UUID(bytes=device_id_bytes)
        
        # Extract payload
        payload = data[17:-2]
        
        # Verify checksum
        received_checksum = struct.unpack('<H', data[-2:])[0]
        calculated_checksum = self._calculate_crc16(data[:-2])
        
        if received_checksum != calculated_checksum:
            print(f"⚠️ Checksum mismatch! Received: {received_checksum:04x}, Calculated: {calculated_checksum:04x}")
            return None
        
        # Parse based on message type
        if message_type == self.MSG_PISTON_STATE and len(payload) >= 2:
            piston_num, state = struct.unpack('<BB', payload[:2])
            return {
                'type': 'piston_command',
                'piston': piston_num,
                'state': 'active' if state == 1 else 'inactive'
            }
        
        return {'type': 'unknown', 'data': payload.hex()}


def simulate_device_activity():
    """
    Simulate a device sending various messages
    """
    # Use the test device ID from the database
    DEVICE_ID = "550e8400-e29b-41d4-a716-446655440000"
    
    print("=" * 60)
    print("🤖 Binary Protocol Simulation")
    print("=" * 60)
    
    client = BinaryProtocolClient(DEVICE_ID)
    client.connect()
    
    try:
        print("\n⏳ Starting simulation (Ctrl+C to stop)...\n")
        time.sleep(2)
        
        cycle = 0
        while True:
            cycle += 1
            print(f"\n{'='*60}")
            print(f"🔄 Cycle {cycle}")
            print(f"{'='*60}")
            
            # Send status update
            battery = random.randint(85, 100)
            signal = random.randint(70, 100)
            client.send_status("online", battery, signal)
            time.sleep(1)
            
            # Activate a random piston
            piston = random.randint(1, 8)
            client.send_piston_state(piston, True)
            time.sleep(1)
            
            # Send telemetry
            temp = round(random.uniform(20.0, 30.0), 2)
            client.send_telemetry("temperature", temp)
            time.sleep(1)
            
            humidity = round(random.uniform(40.0, 70.0), 2)
            client.send_telemetry("humidity", humidity)
            time.sleep(1)
            
            # Deactivate the piston
            client.send_piston_state(piston, False)
            time.sleep(1)
            
            # Wait before next cycle
            print(f"\n⏸  Waiting 5 seconds before next cycle...")
            time.sleep(5)
            
    except KeyboardInterrupt:
        print("\n\n🛑 Stopping simulation...")
        client.disconnect()
        print("✅ Disconnected cleanly")


if __name__ == "__main__":
    simulate_device_activity()
