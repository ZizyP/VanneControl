#!/usr/bin/env python3
"""
IoT Piston Control Device Simulator
Simulates multiple devices with binary protocol communication
"""

import paho.mqtt.client as mqtt
import struct
import time
import uuid
import random
import threading
from dataclasses import dataclass
from typing import List, Optional
from enum import IntEnum
import json
from datetime import datetime

class MessageType(IntEnum):
    """Binary protocol message types"""
    PISTON_STATE = 0x01
    STATUS_UPDATE = 0x02
    TELEMETRY = 0x03
    ERROR = 0x04

class DeviceStatus(IntEnum):
    """Device status codes"""
    OFFLINE = 0
    ONLINE = 1
    ERROR = 2

@dataclass
class Piston:
    """Represents a single piston"""
    number: int
    state: bool = False  # False = inactive, True = active
    
    def toggle(self):
        """Toggle piston state"""
        self.state = not self.state
    
    def activate(self):
        """Activate piston"""
        self.state = True
    
    def deactivate(self):
        """Deactivate piston"""
        self.state = False


class VirtualDevice:
    """Simulates a single IoT device with multiple pistons"""
    
    def __init__(self, device_id: str, name: str, num_pistons: int = 8, broker: str = "localhost", port: int = 1883):
        self.device_id = uuid.UUID(device_id)
        self.name = name
        self.broker = broker
        self.port = port
        
        # Initialize pistons
        self.pistons: List[Piston] = [Piston(number=i+1) for i in range(num_pistons)]
        
        # Device state
        self.status = DeviceStatus.OFFLINE
        self.battery_level = 100
        self.signal_strength = random.randint(70, 100)
        self.temperature = 25.0
        self.pressure = 1013.25
        self.humidity = 50.0
        
        # MQTT client
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, str(self.device_id))
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.on_disconnect = self._on_disconnect
        
        # Control flags
        self.running = False
        self.connected = False
        
        # Statistics
        self.messages_sent = 0
        self.messages_received = 0
        self.errors = 0
    
    def _on_connect(self, client, userdata, flags, rc):
        """Called when connected to MQTT broker"""
        if rc == 0:
            self.connected = True
            self.status = DeviceStatus.ONLINE
            print(f"[{self.name}] ✅ Connected to broker")
            
            # Subscribe to commands
            command_topic = f"devices/{self.device_id}/commands/binary"
            client.subscribe(command_topic)
            print(f"[{self.name}] 📡 Subscribed to: {command_topic}")
            
            # Send initial status
            self.send_status_update()
        else:
            print(f"[{self.name}] ❌ Connection failed with code {rc}")
    
    def _on_disconnect(self, client, userdata, rc):
        """Called when disconnected from broker"""
        self.connected = False
        self.status = DeviceStatus.OFFLINE
        print(f"[{self.name}] 🔌 Disconnected from broker")
    
    def _on_message(self, client, userdata, msg):
        """Called when receiving a command from backend"""
        self.messages_received += 1
        print(f"[{self.name}] 📥 Received command ({len(msg.payload)} bytes)")
        
        try:
            # Parse the binary command
            command = self._parse_command(msg.payload)
            if command:
                print(f"[{self.name}] 🎮 Command: {command}")
                self._execute_command(command)
        except Exception as e:
            print(f"[{self.name}] ❌ Error parsing command: {e}")
            self.errors += 1
    
    def _parse_command(self, data: bytes) -> Optional[dict]:
        """Parse binary command from backend"""
        if len(data) < 19:  # Minimum size
            return None
        
        # Extract message type
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
            print(f"[{self.name}] ⚠️ Checksum mismatch!")
            return None
        
        # Parse based on message type
        if message_type == MessageType.PISTON_STATE:
            piston_num, state = struct.unpack('<BB', payload[:2])
            return {
                'type': 'piston_command',
                'piston_number': piston_num,
                'activate': state == 1
            }
        
        return None
    
    def _execute_command(self, command: dict):
        """Execute a command (simulate hardware control)"""
        if command['type'] == 'piston_command':
            piston_num = command['piston_number']
            activate = command['activate']
            
            if 1 <= piston_num <= len(self.pistons):
                piston = self.pistons[piston_num - 1]
                
                if activate:
                    piston.activate()
                    print(f"[{self.name}] 🔧 Piston #{piston_num} ACTIVATED")
                else:
                    piston.deactivate()
                    print(f"[{self.name}] 🔧 Piston #{piston_num} DEACTIVATED")
                
                # Simulate hardware delay
                time.sleep(0.1)
                
                # Send confirmation back to backend
                self.send_piston_state(piston_num, activate)
            else:
                print(f"[{self.name}] ⚠️ Invalid piston number: {piston_num}")
    
    def connect(self):
        """Connect to MQTT broker"""
        print(f"[{self.name}] 🔌 Connecting to {self.broker}:{self.port}...")
        try:
            self.client.connect(self.broker, self.port, 60)
            self.client.loop_start()
            self.running = True
            time.sleep(1)  # Wait for connection
        except Exception as e:
            print(f"[{self.name}] ❌ Connection error: {e}")
            self.errors += 1
    
    def disconnect(self):
        """Disconnect from MQTT broker"""
        self.running = False
        self.status = DeviceStatus.OFFLINE
        self.send_status_update()
        time.sleep(0.5)
        self.client.loop_stop()
        self.client.disconnect()
        print(f"[{self.name}] 👋 Disconnected")
    
    def _create_message(self, message_type: int, payload: bytes) -> bytes:
        """Create a complete binary message with checksum"""
        header = struct.pack('B', message_type)
        device_id_bytes = self.device_id.bytes
        data = header + device_id_bytes + payload
        checksum = self._calculate_crc16(data)
        return data + struct.pack('<H', checksum)
    
    def _calculate_crc16(self, data: bytes) -> int:
        """Calculate CRC16 checksum"""
        crc = 0xFFFF
        for byte in data:
            crc ^= byte
            for _ in range(8):
                if crc & 0x0001:
                    crc = (crc >> 1) ^ 0x8005
                else:
                    crc >>= 1
        return crc & 0xFFFF
    
    def _publish(self, message: bytes, topic_suffix: str = "binary"):
        """Publish a message to MQTT"""
        topic = f"devices/{self.device_id}/{topic_suffix}"
        try:
            self.client.publish(topic, message, qos=1)
            self.messages_sent += 1
        except Exception as e:
            print(f"[{self.name}] ❌ Publish error: {e}")
            self.errors += 1
    
    def send_piston_state(self, piston_number: int, is_active: bool):
        """Send piston state change message"""
        timestamp = int(time.time() * 1000)
        payload = struct.pack('<BBQ', piston_number, 1 if is_active else 0, timestamp)
        message = self._create_message(MessageType.PISTON_STATE, payload)
        self._publish(message)
        print(f"[{self.name}] 📤 Sent piston #{piston_number} state: {'ACTIVE' if is_active else 'INACTIVE'}")
    
    def send_status_update(self):
        """Send device status update"""
        status_code = self.status.value
        battery = self.battery_level if self.battery_level <= 100 else 255
        signal = self.signal_strength if self.signal_strength <= 100 else 255
        
        payload = struct.pack('<BBB', status_code, battery, signal)
        message = self._create_message(MessageType.STATUS_UPDATE, payload)
        self._publish(message)
        print(f"[{self.name}] 📤 Sent status: {self.status.name}, Battery: {self.battery_level}%, Signal: {self.signal_strength}%")
    
    def send_telemetry(self, sensor_type: str, value: float):
        """Send telemetry data"""
        sensor_codes = {
            'temperature': 0,
            'pressure': 1,
            'humidity': 2,
            'voltage': 3
        }
        
        sensor_code = sensor_codes.get(sensor_type, 0)
        timestamp = int(time.time() * 1000)
        payload = struct.pack('<BfQ', sensor_code, value, timestamp)
        message = self._create_message(MessageType.TELEMETRY, payload)
        self._publish(message)
        print(f"[{self.name}] 📤 Sent telemetry: {sensor_type} = {value:.2f}")
    
    def send_error(self, error_code: int, error_message: str):
        """Send error report"""
        message_bytes = error_message.encode('utf-8')
        payload = struct.pack('<I', error_code) + message_bytes
        message = self._create_message(MessageType.ERROR, payload)
        self._publish(message)
        print(f"[{self.name}] 📤 Sent error: Code {error_code} - {error_message}")
    
    def simulate_environmental_changes(self):
        """Simulate changing environmental conditions"""
        # Temperature drift
        self.temperature += random.uniform(-0.5, 0.5)
        self.temperature = max(15.0, min(35.0, self.temperature))
        
        # Humidity drift
        self.humidity += random.uniform(-2.0, 2.0)
        self.humidity = max(20.0, min(80.0, self.humidity))
        
        # Battery drain
        if self.battery_level > 0:
            self.battery_level -= random.uniform(0.1, 0.3)
            self.battery_level = max(0, self.battery_level)
        
        # Signal fluctuation
        self.signal_strength += random.randint(-5, 5)
        self.signal_strength = max(0, min(100, self.signal_strength))
    
    def get_stats(self) -> dict:
        """Get device statistics"""
        active_pistons = sum(1 for p in self.pistons if p.state)
        return {
            'name': self.name,
            'device_id': str(self.device_id),
            'status': self.status.name,
            'connected': self.connected,
            'active_pistons': f"{active_pistons}/{len(self.pistons)}",
            'battery': f"{self.battery_level:.1f}%",
            'signal': f"{self.signal_strength}%",
            'messages_sent': self.messages_sent,
            'messages_received': self.messages_received,
            'errors': self.errors
        }


class DeviceSimulator:
    """Manages multiple virtual devices"""
    
    def __init__(self, broker: str = "localhost", port: int = 1883):
        self.broker = broker
        self.port = port
        self.devices: List[VirtualDevice] = []
        self.running = False
    
    def add_device(self, device_id: str, name: str, num_pistons: int = 8) -> VirtualDevice:
        """Add a new device to the simulation"""
        device = VirtualDevice(device_id, name, num_pistons, self.broker, self.port)
        self.devices.append(device)
        print(f"➕ Added device: {name} ({device_id})")
        return device
    
    def start_all(self):
        """Start all devices"""
        print(f"\n🚀 Starting {len(self.devices)} devices...\n")
        for device in self.devices:
            device.connect()
            time.sleep(0.5)
        self.running = True
    
    def stop_all(self):
        """Stop all devices"""
        print(f"\n🛑 Stopping {len(self.devices)} devices...\n")
        self.running = False
        for device in self.devices:
            device.disconnect()
            time.sleep(0.3)
    
    def run_scenario(self, scenario_name: str):
        """Run a predefined test scenario"""
        print(f"\n🎬 Running scenario: {scenario_name}\n")
        
        if scenario_name == "random_activity":
            self._scenario_random_activity()
        elif scenario_name == "sequential_pistons":
            self._scenario_sequential_pistons()
        elif scenario_name == "stress_test":
            self._scenario_stress_test()
        elif scenario_name == "telemetry_stream":
            self._scenario_telemetry_stream()
        elif scenario_name == "error_simulation":
            self._scenario_error_simulation()
        else:
            print(f"❌ Unknown scenario: {scenario_name}")
    
    def _scenario_random_activity(self):
        """Random piston activations across all devices"""
        print("📊 Random Activity: Pistons activating randomly for 30 seconds\n")
        start_time = time.time()
        
        while time.time() - start_time < 30 and self.running:
            device = random.choice(self.devices)
            piston = random.choice(device.pistons)
            piston.toggle()
            device.send_piston_state(piston.number, piston.state)
            time.sleep(random.uniform(1, 3))
    
    def _scenario_sequential_pistons(self):
        """Activate pistons sequentially across devices"""
        print("🔢 Sequential Pistons: Wave pattern activation\n")
        
        for device in self.devices:
            print(f"[{device.name}] Starting wave...")
            for piston in device.pistons:
                piston.activate()
                device.send_piston_state(piston.number, True)
                time.sleep(0.5)
            
            time.sleep(1)
            
            for piston in device.pistons:
                piston.deactivate()
                device.send_piston_state(piston.number, False)
                time.sleep(0.5)
            
            print(f"[{device.name}] Wave complete\n")
    
    def _scenario_stress_test(self):
        """Rapid fire messages to test system limits"""
        print("⚡ Stress Test: Rapid message bursts for 20 seconds\n")
        start_time = time.time()
        
        while time.time() - start_time < 20 and self.running:
            for device in self.devices:
                piston_num = random.randint(1, len(device.pistons))
                state = random.choice([True, False])
                device.send_piston_state(piston_num, state)
            time.sleep(0.1)  # 10 messages/second per device
    
    def _scenario_telemetry_stream(self):
        """Continuous telemetry updates"""
        print("📡 Telemetry Stream: Environmental data for 30 seconds\n")
        start_time = time.time()
        
        while time.time() - start_time < 30 and self.running:
            for device in self.devices:
                device.simulate_environmental_changes()
                device.send_telemetry('temperature', device.temperature)
                time.sleep(1)
                device.send_telemetry('humidity', device.humidity)
                time.sleep(1)
                device.send_status_update()
            time.sleep(3)
    
    def _scenario_error_simulation(self):
        """Simulate various error conditions"""
        print("⚠️ Error Simulation: Generating error reports\n")
        
        error_conditions = [
            (503, "Sensor malfunction detected"),
            (404, "Piston actuator not responding"),
            (500, "System overheating warning"),
            (101, "Low battery warning")
        ]
        
        for device in self.devices:
            error_code, error_msg = random.choice(error_conditions)
            device.send_error(error_code, error_msg)
            time.sleep(2)
    
    def print_stats(self):
        """Print statistics for all devices"""
        print("\n" + "="*80)
        print("📊 DEVICE STATISTICS")
        print("="*80)
        
        for device in self.devices:
            stats = device.get_stats()
            print(f"\n🔧 {stats['name']}")
            print(f"   ID: {stats['device_id']}")
            print(f"   Status: {stats['status']} | Connected: {stats['connected']}")
            print(f"   Active Pistons: {stats['active_pistons']}")
            print(f"   Battery: {stats['battery']} | Signal: {stats['signal']}")
            print(f"   Messages: Sent={stats['messages_sent']}, Received={stats['messages_received']}, Errors={stats['errors']}")
        
        print("\n" + "="*80 + "\n")


def main():
    """Main simulation program"""
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║     🎮 IoT Device Simulator - Binary Protocol           ║
    ║                                                          ║
    ║     Simulates multiple devices with binary MQTT         ║
    ║     communication for testing the backend system        ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    # Create simulator
    sim = DeviceSimulator(broker="localhost", port=1883)
    
    # Add devices
    sim.add_device("550e8400-e29b-41d4-a716-446655440000", "Factory Floor Unit 1", num_pistons=8)
    sim.add_device("660e8400-e29b-41d4-a716-446655440001", "Factory Floor Unit 2", num_pistons=8)
    sim.add_device("770e8400-e29b-41d4-a716-446655440002", "Warehouse Unit 1", num_pistons=6)
    
    # Start all devices
    sim.start_all()
    
    try:
        # Interactive menu
        while True:
            print("\n" + "="*60)
            print("🎮 SIMULATOR MENU")
            print("="*60)
            print("1. Random Activity (30s)")
            print("2. Sequential Pistons")
            print("3. Stress Test (20s)")
            print("4. Telemetry Stream (30s)")
            print("5. Error Simulation")
            print("6. Show Statistics")
            print("7. Send Custom Command")
            print("8. Quit")
            print("="*60)
            
            choice = input("\nSelect option (1-8): ").strip()
            
            if choice == '1':
                sim.run_scenario('random_activity')
            elif choice == '2':
                sim.run_scenario('sequential_pistons')
            elif choice == '3':
                sim.run_scenario('stress_test')
            elif choice == '4':
                sim.run_scenario('telemetry_stream')
            elif choice == '5':
                sim.run_scenario('error_simulation')
            elif choice == '6':
                sim.print_stats()
            elif choice == '7':
                # Custom command
                print("\n📋 Devices:")
                for i, dev in enumerate(sim.devices):
                    print(f"  {i+1}. {dev.name}")
                dev_idx = int(input("Select device: ")) - 1
                piston_num = int(input("Piston number (1-8): "))
                action = input("Action (activate/deactivate): ").strip().lower()
                
                device = sim.devices[dev_idx]
                is_active = (action == 'activate')
                device.send_piston_state(piston_num, is_active)
            elif choice == '8':
                break
            else:
                print("❌ Invalid option")
    
    except KeyboardInterrupt:
        print("\n\n⚠️ Interrupted by user")
    finally:
        sim.stop_all()
        print("\n✅ Simulation ended\n")


if __name__ == "__main__":
    main()
