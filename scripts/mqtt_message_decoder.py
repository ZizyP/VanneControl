#!/usr/bin/env python3
"""
MQTT Binary Message Decoder for IoT Piston Control System

This script subscribes to MQTT topics and decodes binary protocol messages
in real-time, showing you exactly what data is being transmitted.

Usage:
    python3 mqtt_message_decoder.py
"""

import paho.mqtt.client as mqtt
import struct
import uuid
import json
from datetime import datetime
from typing import Optional, Dict, Any

# MQTT Configuration
BROKER = "localhost"
PORT = 1883
TOPICS = [
    "devices/#",  # Subscribe to all device topics
]

# Binary Protocol Constants
MSG_PISTON_STATE = 0x01
MSG_STATUS_UPDATE = 0x02
MSG_TELEMETRY = 0x03
MSG_ERROR = 0x04

class BinaryMessageDecoder:
    """Decodes binary protocol messages from IoT devices"""
    
    def __init__(self):
        self.message_count = 0
        self.start_time = datetime.now()
    
    def calculate_crc16(self, data: bytes) -> int:
        """Calculate CRC16-CCITT checksum"""
        crc = 0xFFFF
        for byte in data:
            crc ^= byte << 8
            for _ in range(8):
                if crc & 0x8000:
                    crc = (crc << 1) ^ 0x1021
                else:
                    crc = crc << 1
                crc &= 0xFFFF
        return crc
    
    def decode_binary_message(self, payload: bytes) -> Optional[Dict[str, Any]]:
        """
        Decode a binary protocol message
        
        Format:
        [1 byte]  Message Type
        [16 bytes] Device UUID
        [variable] Payload
        [2 bytes]  CRC16 checksum
        """
        
        if len(payload) < 19:  # Minimum: 1 + 16 + 2
            return None
        
        try:
            # Extract message type
            message_type = payload[0]
            
            # Extract device UUID (16 bytes)
            device_uuid_bytes = payload[1:17]
            device_uuid = str(uuid.UUID(bytes=device_uuid_bytes))
            
            # Verify CRC (last 2 bytes)
            data_without_crc = payload[:-2]
            received_crc = struct.unpack('<H', payload[-2:])[0]
            calculated_crc = self.calculate_crc16(data_without_crc)
            
            crc_valid = received_crc == calculated_crc
            
            # Extract payload data (between UUID and CRC)
            payload_data = payload[17:-2]
            
            # Decode based on message type
            decoded = {
                'device_id': device_uuid,
                'message_type': message_type,
                'message_type_name': self.get_message_type_name(message_type),
                'crc_valid': crc_valid,
                'received_crc': f"0x{received_crc:04X}",
                'calculated_crc': f"0x{calculated_crc:04X}",
                'raw_length': len(payload),
                'timestamp': datetime.now().isoformat()
            }
            
            if message_type == MSG_PISTON_STATE:
                decoded['data'] = self.decode_piston_state(payload_data)
            elif message_type == MSG_STATUS_UPDATE:
                decoded['data'] = self.decode_status_update(payload_data)
            elif message_type == MSG_TELEMETRY:
                decoded['data'] = self.decode_telemetry(payload_data)
            elif message_type == MSG_ERROR:
                decoded['data'] = self.decode_error(payload_data)
            else:
                decoded['data'] = {
                    'raw_hex': payload_data.hex(),
                    'raw_ascii': self.safe_ascii(payload_data)
                }
            
            return decoded
            
        except Exception as e:
            return {
                'error': str(e),
                'raw_hex': payload.hex(),
                'raw_length': len(payload)
            }
    
    def decode_piston_state(self, payload: bytes) -> Dict[str, Any]:
        """Decode piston state change message"""
        if len(payload) >= 10:
            piston_num, state = struct.unpack('<BB', payload[:2])
            timestamp = struct.unpack('<Q', payload[2:10])[0]
            
            return {
                'piston_number': piston_num,
                'state': 'ACTIVE' if state == 1 else 'INACTIVE',
                'state_raw': state,
                'timestamp': timestamp,
                'timestamp_readable': datetime.fromtimestamp(timestamp).isoformat()
            }
        return {'raw_hex': payload.hex()}
    
    def decode_status_update(self, payload: bytes) -> Dict[str, Any]:
        """Decode device status update message"""
        if len(payload) >= 3:
            status_byte = payload[0]
            battery = None
            signal = None
            
            # Status string length (next byte)
            if len(payload) > 1:
                status_len = payload[1]
                if len(payload) >= 2 + status_len:
                    status_str = payload[2:2+status_len].decode('utf-8', errors='ignore')
                    
                    # Battery and signal (optional, after status string)
                    offset = 2 + status_len
                    if len(payload) >= offset + 2:
                        battery, signal = struct.unpack('<BB', payload[offset:offset+2])
                    
                    return {
                        'status': status_str,
                        'battery_level': battery,
                        'signal_strength': signal,
                        'battery_icon': self.battery_icon(battery),
                        'signal_icon': self.signal_icon(signal)
                    }
            
            return {'status_byte': status_byte, 'raw_hex': payload.hex()}
        return {'raw_hex': payload.hex()}
    
    def decode_telemetry(self, payload: bytes) -> Dict[str, Any]:
        """Decode telemetry data message"""
        if len(payload) >= 13:
            # Sensor type string length
            sensor_len = payload[0]
            if len(payload) >= 1 + sensor_len + 12:
                sensor_type = payload[1:1+sensor_len].decode('utf-8', errors='ignore')
                offset = 1 + sensor_len
                
                value = struct.unpack('<f', payload[offset:offset+4])[0]
                timestamp = struct.unpack('<Q', payload[offset+4:offset+12])[0]
                
                return {
                    'sensor_type': sensor_type,
                    'value': round(value, 2),
                    'timestamp': timestamp,
                    'timestamp_readable': datetime.fromtimestamp(timestamp).isoformat(),
                    'formatted': f"{sensor_type}: {value:.2f}"
                }
        
        return {'raw_hex': payload.hex()}
    
    def decode_error(self, payload: bytes) -> Dict[str, Any]:
        """Decode error report message"""
        if len(payload) >= 34:
            error_code = struct.unpack('<H', payload[:2])[0]
            error_msg_bytes = payload[2:34]
            # Remove null padding
            error_msg = error_msg_bytes.rstrip(b'\x00').decode('utf-8', errors='ignore')
            
            return {
                'error_code': error_code,
                'error_message': error_msg,
                'severity': self.get_error_severity(error_code)
            }
        
        return {'raw_hex': payload.hex()}
    
    def get_message_type_name(self, msg_type: int) -> str:
        """Get human-readable message type name"""
        types = {
            MSG_PISTON_STATE: "PISTON_STATE",
            MSG_STATUS_UPDATE: "STATUS_UPDATE",
            MSG_TELEMETRY: "TELEMETRY",
            MSG_ERROR: "ERROR_REPORT"
        }
        return types.get(msg_type, f"UNKNOWN(0x{msg_type:02X})")
    
    def get_error_severity(self, code: int) -> str:
        """Determine error severity from code"""
        if code < 400:
            return "INFO"
        elif code < 500:
            return "WARNING"
        else:
            return "ERROR"
    
    def battery_icon(self, level: Optional[int]) -> str:
        """Get battery icon based on level"""
        if level is None:
            return "❓"
        if level >= 80:
            return "🔋"
        elif level >= 50:
            return "🔋"
        elif level >= 20:
            return "🪫"
        else:
            return "🪫"
    
    def signal_icon(self, strength: Optional[int]) -> str:
        """Get signal icon based on strength"""
        if strength is None:
            return "❓"
        if strength >= 80:
            return "📶"
        elif strength >= 50:
            return "📶"
        elif strength >= 20:
            return "📶"
        else:
            return "📵"
    
    def safe_ascii(self, data: bytes) -> str:
        """Convert bytes to safe ASCII representation"""
        return ''.join(chr(b) if 32 <= b < 127 else '.' for b in data)
    
    def try_decode_json(self, payload: bytes) -> Optional[Dict[str, Any]]:
        """Try to decode payload as JSON"""
        try:
            text = payload.decode('utf-8')
            return json.loads(text)
        except:
            return None
    
    def format_output(self, topic: str, decoded: Dict[str, Any], raw: bytes):
        """Pretty print decoded message"""
        self.message_count += 1
        
        print("\n" + "═" * 70)
        print(f"📨 Message #{self.message_count} | {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")
        print("─" * 70)
        print(f"📍 Topic: {topic}")
        print(f"📦 Size:  {len(raw)} bytes")
        
        if 'error' in decoded:
            print(f"\n❌ Decode Error: {decoded['error']}")
            print(f"📄 Raw Hex: {decoded.get('raw_hex', '')[:100]}")
            return
        
        print(f"\n🔖 Message Type: {decoded['message_type_name']}")
        print(f"🆔 Device ID:    {decoded['device_id'][:8]}...{decoded['device_id'][-4:]}")
        
        # CRC validation
        if decoded['crc_valid']:
            print(f"✅ CRC Valid:    {decoded['received_crc']}")
        else:
            print(f"❌ CRC INVALID:  Received {decoded['received_crc']}, Expected {decoded['calculated_crc']}")
        
        # Decode specific data
        if 'data' in decoded:
            print("\n📊 Decoded Data:")
            self.print_data(decoded['data'], indent=3)
        
        print("─" * 70)
    
    def print_data(self, data: Dict[str, Any], indent: int = 0):
        """Recursively print dictionary with indentation"""
        prefix = " " * indent
        for key, value in data.items():
            if isinstance(value, dict):
                print(f"{prefix}• {key}:")
                self.print_data(value, indent + 2)
            else:
                # Add icons for specific fields
                icon = ""
                if key == "state" and value == "ACTIVE":
                    icon = "🟢 "
                elif key == "state" and value == "INACTIVE":
                    icon = "⚫ "
                elif key == "error_code":
                    icon = "🔴 "
                elif key in ["battery_level", "battery_icon"]:
                    icon = ""
                elif key in ["signal_strength", "signal_icon"]:
                    icon = ""
                
                print(f"{prefix}• {key}: {icon}{value}")


class MQTTDecoder:
    """MQTT client that decodes messages in real-time"""
    
    def __init__(self):
        self.decoder = BinaryMessageDecoder()
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, "mqtt-decoder")
        self.client.on_connect = self.on_connect
        self.client.on_message = self.on_message
    
    def on_connect(self, client, userdata, flags, rc):
        """Callback when connected to MQTT broker"""
        if rc == 0:
            print("╔═════════════════════════════════════════════════════════════╗")
            print("║         MQTT Binary Message Decoder - Connected            ║")
            print("╚═════════════════════════════════════════════════════════════╝")
            print(f"\n✅ Connected to MQTT broker at {BROKER}:{PORT}")
            print(f"🎯 Subscribing to topics:")
            
            for topic in TOPICS:
                client.subscribe(topic)
                print(f"   • {topic}")
            
            print("\n👀 Listening for messages... (Press Ctrl+C to stop)\n")
        else:
            print(f"❌ Connection failed with code {rc}")
    
    def on_message(self, client, userdata, msg):
        """Callback when message received"""
        
        # First, try to decode as JSON (for backward compatibility)
        json_data = self.decoder.try_decode_json(msg.payload)
        
        if json_data:
            # It's a JSON message
            self.decoder.message_count += 1
            print("\n" + "═" * 70)
            print(f"📨 Message #{self.decoder.message_count} | {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")
            print("─" * 70)
            print(f"📍 Topic: {msg.topic}")
            print(f"📦 Format: JSON")
            print(f"📄 Data:\n")
            print(json.dumps(json_data, indent=2))
            print("─" * 70)
        else:
            # Try to decode as binary
            decoded = self.decoder.decode_binary_message(msg.payload)
            if decoded:
                self.decoder.format_output(msg.topic, decoded, msg.payload)
            else:
                # Unknown format
                self.decoder.message_count += 1
                print("\n" + "═" * 70)
                print(f"📨 Message #{self.decoder.message_count} | {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")
                print("─" * 70)
                print(f"📍 Topic: {msg.topic}")
                print(f"❓ Format: Unknown/Raw")
                print(f"📦 Size: {len(msg.payload)} bytes")
                print(f"📄 Raw Hex: {msg.payload.hex()[:100]}")
                print(f"📝 ASCII: {self.decoder.safe_ascii(msg.payload)[:100]}")
                print("─" * 70)
    
    def run(self):
        """Connect and start listening"""
        try:
            self.client.connect(BROKER, PORT, 60)
            self.client.loop_forever()
        except KeyboardInterrupt:
            print("\n\n🛑 Stopping decoder...")
            self.print_statistics()
        except Exception as e:
            print(f"\n❌ Error: {e}")
            print(f"   Make sure MQTT broker is running:")
            print(f"   docker compose ps mosquitto")
    
    def print_statistics(self):
        """Print session statistics"""
        uptime = (datetime.now() - self.decoder.start_time).total_seconds()
        
        print("\n╔═════════════════════════════════════════════════════════════╗")
        print("║                    SESSION STATISTICS                       ║")
        print("╚═════════════════════════════════════════════════════════════╝")
        print(f"\n📊 Messages decoded: {self.decoder.message_count}")
        print(f"⏱️  Session duration: {uptime:.1f} seconds")
        print(f"📈 Messages/second: {self.decoder.message_count/uptime:.2f}" if uptime > 0 else "")
        print("\n✅ Decoder stopped cleanly\n")


def main():
    """Main entry point"""
    print("""
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║         MQTT Binary Protocol Message Decoder                  ║
║                                                               ║
║  This tool decodes binary protocol messages from IoT          ║
║  devices in real-time, showing you:                           ║
║                                                               ║
║  • Message type and device ID                                 ║
║  • CRC validation status                                      ║
║  • Decoded payload data                                       ║
║  • Piston states, telemetry, errors                           ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
    """)
    
    print("🔧 Configuration:")
    print(f"   Broker: {BROKER}:{PORT}")
    print(f"   Topics: {', '.join(TOPICS)}")
    print()
    
    decoder = MQTTDecoder()
    decoder.run()


if __name__ == "__main__":
    main()
