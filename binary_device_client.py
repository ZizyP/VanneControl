#!/usr/bin/env python3
"""
Binary Protocol Device Client
Simulates a Raspberry Pi sending binary messages via MQTT

This demonstrates:
1. Creating binary messages according to protocol spec
2. Calculating CRC16 checksums
3. Publishing to MQTT broker
"""

import paho.mqtt.client as mqtt
import struct
import time
import uuid
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
            
            # Execute the command (simulate hardware control)
            if command:
                self._execute_command(command)
                
        except Exception as e:
            print(f"❌ Error parsing command: {e}")
    
    def connect(self):
        """Connect to MQTT broker"""
        print(f"\n🚀 Connecting to {self.broker}:{self.port}...")
        self.client.connect(self.broker, self.port, 60)
        self.client.loop_start()
        time.sleep(1)  # Wait for connection
    
    def disconnect(self):
        """Disconnect from MQTT broker"""
        print("\n🛑 Disconnecting...")
        self.client.loop_stop()
        self.client.disconnect()
    
    def send_piston_state(self, piston_number: int, is_active: bool):
        """
        Send piston state change message
        
        Binary Format:
        [0x01] [UUID: 16 bytes] [piston_num: 1 byte] [state: 1 byte] [timestamp: 8 bytes] [CRC: 2 bytes]
        """
        print(f"\n📤 Sending piston state: #{piston_number} -> {'ACTIVE' if is_active else 'INACTIVE'}")
        
        # Build payload
        timestamp = int(time.time() * 1000)  # milliseconds
        payload = struct.pack('<BBQ', piston_number, 1 if is_active else 0, timestamp)
        
        # Create complete message
        message = self._create_message(self.MSG_PISTON_STATE, payload)
        
        # Publish to binary topic
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Sent {len(message)} bytes to {topic}")
    
    def send_status_update(self, status: str, battery_level: Optional[int] = None, 
                          signal_strength: Optional[int] = None):
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
        
        timestamp = int(time.time() * 1000)
        payload = struct.pack('<BfQ', sensor_code, value, timestamp)
        message = self._create_message(self.MSG_TELEMETRY, payload)
        
        topic = f"devices/{self.device_id}/binary"
        self.client.publish(topic, message, qos=1)
        
        print(f"   ✓ Sent {sensor_type} reading: {value}")
    
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
        
        # Device ID (UUID as 16 bytes)
        device_id_bytes = self.device_id.bytes
        
        # Combine header + device ID + payload
        data = header + device_id_bytes + payload
        
        # Calculate CRC16 checksum
        checksum = self._calculate_crc16(data)
        
        # Append checksum
        return data + struct.pack('<H', checksum)
    
    def _calculate_crc16(self, data: bytes) -> int:
        """
        Calculate CRC16 checksum (must match backend implementation)
        """
        crc = 0xFFFF
        
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8005
                else:
                    crc >>= 1
        
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
            print(f"⚠️ Checksum mismatch!")
            return None
        
        # Parse based on message type
        if message_type == self.MSG_PISTON_STATE:
            piston_num, state = struct.unpack('<BB', payload[:2])
            return {
                'type': 'piston_command',
                'piston_number': piston_num,
                'activate': state == 1
            }
        
        return None
    
    def _execute_command(self, command: dict):
        """Simulate executing a hardware command"""
        if command['type'] == 'piston_command':
            piston = command['piston_number']
            activate = command['activate']
            
            print(f"🔧 Executing: Piston #{piston} -> {'ACTIVATE' if activate else 'DEACTIVATE'}")
            
            # Simulate hardware delay
            time.sleep(0.1)
            
            # Send confirmation back to backend
            self.send_piston_state(piston, activate)


def main():
    """
    Main demo function
    """
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║     🔧 Binary Protocol Device Simulator                 ║
    ║                                                          ║
    ║     Testing binary message protocol with:               ║
    ║     • Piston state changes                              ║
    ║     • Status updates                                    ║
    ║     • Telemetry data                                    ║
    ║     • Error reports                                     ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    # Create a device with a known UUID for testing
    device_id = "550e8400-e29b-41d4-a716-446655440000"
    client = BinaryProtocolClient(device_id)
    
    try:
        # Connect to broker
        client.connect()
        
        # Demo sequence
        print("\n" + "="*60)
        print("DEMO SEQUENCE - Sending binary messages every 3 seconds")
        print("="*60)
        
        # 1. Initial status update
        client.send_status_update("online", battery_level=95, signal_strength=85)
        time.sleep(3)
        
        # 2. Activate piston 3
        client.send_piston_state(3, True)
        time.sleep(3)
        
        # 3. Send some telemetry
        client.send_telemetry("temperature", 23.5)
        time.sleep(2)
        client.send_telemetry("humidity", 65.2)
        time.sleep(2)
        
        # 4. Deactivate piston 3
        client.send_piston_state(3, False)
        time.sleep(3)
        
        # 5. Activate multiple pistons
        for piston in [1, 2, 4, 5]:
            client.send_piston_state(piston, True)
            time.sleep(1)
        
        time.sleep(2)
        
        # 6. Send telemetry with different values
        client.send_telemetry("voltage", 12.3)
        time.sleep(2)
        client.send_telemetry("pressure", 1013.25)
        time.sleep(3)
        
        # 7. Simulate an error
        client.send_error(503, "Piston 7 sensor malfunction")
        time.sleep(3)
        
        # 8. Deactivate all pistons
        for piston in [1, 2, 4, 5]:
            client.send_piston_state(piston, False)
            time.sleep(1)
        
        # 9. Final status update
        client.send_status_update("online", battery_level=92, signal_strength=80)
        
        print("\n" + "="*60)
        print("DEMO COMPLETE - Listening for commands...")
        print("Press Ctrl+C to exit")
        print("="*60)
        
        # Keep running and listening for commands
        while True:
            time.sleep(10)
            # Periodic status update
            client.send_status_update("online", battery_level=90, signal_strength=75)
            
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        client.disconnect()
        print("✅ Clean shutdown complete")


if __name__ == "__main__":
    main()
