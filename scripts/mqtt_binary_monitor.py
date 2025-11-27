#!/usr/bin/env python3
"""
MQTT Binary Protocol Monitor
Real-time monitor that properly decodes binary messages from MQTT

This fixes the "year out of range" errors by correctly parsing
the binary protocol format.
"""

import paho.mqtt.client as mqtt
import struct
import uuid
from datetime import datetime
from typing import Optional
import sys

class BinaryMessageDecoder:
    """Decodes binary protocol messages"""
    
    MSG_TYPES = {
        0x01: "PISTON_STATE",
        0x02: "STATUS_UPDATE",
        0x03: "TELEMETRY",
        0x04: "ERROR"
    }
    
    SENSOR_TYPES = {
        0: "temperature",
        1: "pressure",
        2: "humidity",
        3: "voltage"
    }
    
    STATUS_CODES = {
        0: "offline",
        1: "online",
        2: "error"
    }
    
    def __init__(self):
        self.message_count = 0
        self.crc_errors = 0
        self.decode_errors = 0
    
    def calculate_crc16(self, data: bytes) -> int:
        """Calculate CRC16 checksum"""
        crc = 0xFFFF
        for byte_val in data:
            crc ^= byte_val
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8005
                else:
                    crc >>= 1
        return crc & 0xFFFF
    
    def verify_crc(self, data: bytes) -> bool:
        """Verify message CRC"""
        if len(data) < 19:  # Minimum message size
            return False
        
        # CRC is last 2 bytes
        received_crc = struct.unpack('<H', data[-2:])[0]
        # Calculate CRC on everything except the CRC itself
        calculated_crc = self.calculate_crc16(data[:-2])
        
        return received_crc == calculated_crc
    
    def decode(self, data: bytes) -> Optional[dict]:
        """Decode binary message"""
        self.message_count += 1
        
        try:
            if len(data) < 19:
                self.decode_errors += 1
                return {
                    'error': 'Message too short',
                    'size': len(data),
                    'hex': data.hex()
                }
            
            # Verify CRC
            if not self.verify_crc(data):
                self.crc_errors += 1
                received_crc = struct.unpack('<H', data[-2:])[0]
                calculated_crc = self.calculate_crc16(data[:-2])
                return {
                    'error': 'CRC mismatch',
                    'received_crc': f"0x{received_crc:04x}",
                    'calculated_crc': f"0x{calculated_crc:04x}",
                    'hex': data.hex()
                }
            
            # Parse header
            msg_type = data[0]
            
            # Parse UUID (16 bytes, big-endian)
            device_uuid = uuid.UUID(bytes=data[1:17])
            
            # Parse payload
            payload = data[17:-2]
            
            # CRC
            crc = struct.unpack('<H', data[-2:])[0]
            
            # Decode based on message type
            if msg_type == 0x01:  # PISTON_STATE
                return self._decode_piston_state(device_uuid, payload, crc)
            elif msg_type == 0x02:  # STATUS_UPDATE
                return self._decode_status_update(device_uuid, payload, crc)
            elif msg_type == 0x03:  # TELEMETRY
                return self._decode_telemetry(device_uuid, payload, crc)
            elif msg_type == 0x04:  # ERROR
                return self._decode_error(device_uuid, payload, crc)
            else:
                return {
                    'error': 'Unknown message type',
                    'type': f"0x{msg_type:02x}",
                    'device_id': str(device_uuid),
                    'hex': data.hex()
                }
        
        except Exception as e:
            self.decode_errors += 1
            return {
                'error': f'Decode exception: {e}',
                'hex': data.hex()
            }
    
    def _decode_piston_state(self, device_uuid: uuid.UUID, payload: bytes, crc: int) -> dict:
        """Decode piston state message"""
        if len(payload) < 10:
            return {'error': 'Invalid piston state payload size', 'size': len(payload)}
        
        piston_num, state_byte = struct.unpack('<BB', payload[0:2])
        timestamp_ms = struct.unpack('<Q', payload[2:10])[0]
        
        # Convert timestamp from milliseconds to datetime
        timestamp = datetime.fromtimestamp(timestamp_ms / 1000)
        
        return {
            'type': 'PISTON_STATE',
            'device_id': str(device_uuid)[:8] + '...',
            'piston': piston_num,
            'state': 'ACTIVE' if state_byte == 1 else 'INACTIVE',
            'timestamp': timestamp.strftime('%H:%M:%S.%f')[:-3],
            'crc': f"0x{crc:04x}",
            '✓': 'CRC Valid'
        }
    
    def _decode_status_update(self, device_uuid: uuid.UUID, payload: bytes, crc: int) -> dict:
        """Decode status update message"""
        if len(payload) < 3:
            return {'error': 'Invalid status update payload size', 'size': len(payload)}
        
        status_code, battery, signal = struct.unpack('<BBB', payload[0:3])
        
        return {
            'type': 'STATUS_UPDATE',
            'device_id': str(device_uuid)[:8] + '...',
            'status': self.STATUS_CODES.get(status_code, f"unknown({status_code})"),
            'battery': f"{battery}%" if battery != 255 else "N/A",
            'signal': f"{signal}%" if signal != 255 else "N/A",
            'crc': f"0x{crc:04x}",
            '✓': 'CRC Valid'
        }
    
    def _decode_telemetry(self, device_uuid: uuid.UUID, payload: bytes, crc: int) -> dict:
        """Decode telemetry message"""
        if len(payload) < 13:
            return {'error': 'Invalid telemetry payload size', 'size': len(payload)}
        
        sensor_code = payload[0]
        value = struct.unpack('<f', payload[1:5])[0]
        timestamp_ms = struct.unpack('<Q', payload[5:13])[0]
        
        # Convert timestamp from milliseconds to datetime
        timestamp = datetime.fromtimestamp(timestamp_ms / 1000)
        
        sensor_name = self.SENSOR_TYPES.get(sensor_code, f"unknown({sensor_code})")
        
        return {
            'type': 'TELEMETRY',
            'device_id': str(device_uuid)[:8] + '...',
            'sensor': sensor_name,
            'value': f"{value:.2f}",
            'timestamp': timestamp.strftime('%H:%M:%S.%f')[:-3],
            'crc': f"0x{crc:04x}",
            '✓': 'CRC Valid'
        }
    
    def _decode_error(self, device_uuid: uuid.UUID, payload: bytes, crc: int) -> dict:
        """Decode error message"""
        if len(payload) < 4:
            return {'error': 'Invalid error payload size', 'size': len(payload)}
        
        error_code = struct.unpack('<I', payload[0:4])[0]
        error_msg = payload[4:].decode('utf-8', errors='replace')
        
        return {
            'type': 'ERROR',
            'device_id': str(device_uuid)[:8] + '...',
            'code': error_code,
            'message': error_msg,
            'crc': f"0x{crc:04x}",
            '✓': 'CRC Valid'
        }


class MQTTBinaryMonitor:
    """MQTT monitor with binary protocol support"""
    
    def __init__(self, broker: str = "localhost", port: int = 1883):
        self.broker = broker
        self.port = port
        self.decoder = BinaryMessageDecoder()
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, "binary-monitor")
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        
        # Color codes for terminal
        self.COLORS = {
            'RESET': '\033[0m',
            'BOLD': '\033[1m',
            'GREEN': '\033[92m',
            'YELLOW': '\033[93m',
            'RED': '\033[91m',
            'BLUE': '\033[94m',
            'CYAN': '\033[96m',
            'MAGENTA': '\033[95m'
        }
    
    def _color(self, text: str, color: str) -> str:
        """Colorize text"""
        return f"{self.COLORS.get(color, '')}{text}{self.COLORS['RESET']}"
    
    def _on_connect(self, client, userdata, flags, rc):
        """Handle MQTT connection"""
        if rc == 0:
            print(self._color("✅ Connected to MQTT broker", "GREEN"))
            # Subscribe to all device binary topics
            client.subscribe("devices/+/binary")
            print(self._color("📡 Subscribed to: devices/+/binary", "CYAN"))
            print(self._color("👀 Monitoring messages... (Ctrl+C to stop)\n", "YELLOW"))
        else:
            print(self._color(f"❌ Connection failed with code {rc}", "RED"))
    
    def _on_message(self, client, userdata, msg):
        """Handle incoming MQTT message"""
        timestamp = datetime.now().strftime('%H:%M:%S.%f')[:-3]
        
        # Print separator
        print(self._color("═" * 70, "BLUE"))
        print(f"{self._color('📨 Message', 'BOLD')} | {timestamp}")
        print(self._color("─" * 70, "BLUE"))
        
        # Print topic and size
        print(f"{self._color('📍 Topic:', 'CYAN')} {msg.topic}")
        print(f"{self._color('📦 Size:', 'CYAN')}  {len(msg.payload)} bytes")
        print()
        
        # Decode message
        decoded = self.decoder.decode(msg.payload)
        
        if 'error' in decoded:
            # Error case
            print(self._color(f"❌ {decoded['error']}", "RED"))
            if 'received_crc' in decoded:
                print(f"   Received CRC:   {decoded['received_crc']}")
                print(f"   Calculated CRC: {decoded['calculated_crc']}")
            if 'hex' in decoded:
                print(f"   Raw Hex: {decoded['hex'][:80]}...")
        else:
            # Successful decode
            msg_type = decoded.get('type', 'UNKNOWN')
            type_colors = {
                'PISTON_STATE': 'MAGENTA',
                'STATUS_UPDATE': 'GREEN',
                'TELEMETRY': 'CYAN',
                'ERROR': 'RED'
            }
            color = type_colors.get(msg_type, 'YELLOW')
            
            print(self._color(f"🔖 Type: {msg_type}", color))
            print(f"🆔 Device: {decoded.get('device_id', 'N/A')}")
            
            # Print type-specific fields
            if msg_type == 'PISTON_STATE':
                print(f"🔧 Piston #{decoded['piston']}: {self._color(decoded['state'], 'BOLD')}")
                print(f"⏰ Time: {decoded['timestamp']}")
            
            elif msg_type == 'STATUS_UPDATE':
                print(f"📊 Status: {decoded['status']}")
                print(f"🔋 Battery: {decoded['battery']}")
                print(f"📶 Signal: {decoded['signal']}")
            
            elif msg_type == 'TELEMETRY':
                print(f"🌡️  Sensor: {decoded['sensor']}")
                print(f"📈 Value: {decoded['value']}")
                print(f"⏰ Time: {decoded['timestamp']}")
            
            elif msg_type == 'ERROR':
                print(f"⚠️  Code: {decoded['code']}")
                print(f"💬 Message: {decoded['message']}")
            
            print(f"✅ {decoded.get('✓', 'Valid')}: {decoded.get('crc', 'N/A')}")
        
        print()
    
    def run(self):
        """Start monitoring"""
        print(self._color("=" * 70, "BOLD"))
        print(self._color("     🔍 MQTT BINARY PROTOCOL MONITOR", "BOLD"))
        print(self._color("=" * 70, "BOLD"))
        print(f"Broker: {self.broker}:{self.port}")
        print(self._color("=" * 70, "BOLD"))
        print()
        
        try:
            self.client.connect(self.broker, self.port, 60)
            self.client.loop_forever()
        
        except KeyboardInterrupt:
            print(self._color("\n\n👋 Stopping monitor...", "YELLOW"))
            self._print_stats()
        
        except Exception as e:
            print(self._color(f"\n❌ Error: {e}", "RED"))
        
        finally:
            self.client.disconnect()
    
    def _print_stats(self):
        """Print statistics"""
        print(self._color("\n📊 Statistics:", "BOLD"))
        print(f"   Total messages: {self.decoder.message_count}")
        print(f"   CRC errors: {self._color(str(self.decoder.crc_errors), 'RED' if self.decoder.crc_errors > 0 else 'GREEN')}")
        print(f"   Decode errors: {self._color(str(self.decoder.decode_errors), 'RED' if self.decoder.decode_errors > 0 else 'GREEN')}")
        print()


if __name__ == "__main__":
    broker = sys.argv[1] if len(sys.argv) > 1 else "localhost"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 1883
    
    monitor = MQTTBinaryMonitor(broker, port)
    monitor.run()
