#!/usr/bin/env python3
"""
WebSocket Real-Time Monitor for IoT Piston Control System

This script demonstrates what you can see with WebSocket monitoring:
- Connection establishment
- Device subscription
- Real-time status updates
- Piston state changes
- System events
"""

import asyncio
import websockets
import json
import sys
from datetime import datetime

class WebSocketMonitor:
    def __init__(self, ws_url, device_id):
        self.ws_url = ws_url
        self.device_id = device_id
        self.session_id = None
        self.message_count = 0
        self.start_time = datetime.now()
    
    def log(self, emoji, message, data=None):
        """Pretty print log messages"""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        print(f"{timestamp} {emoji} {message}")
        if data:
            print(f"         └─ {json.dumps(data, indent=11)[11:]}")
    
    async def monitor(self):
        """Connect and monitor WebSocket messages"""
        try:
            self.log("🔌", "Connecting to WebSocket...")
            
            async with websockets.connect(self.ws_url) as websocket:
                self.log("✅", "Connected to WebSocket server")
                
                # Wait for connection confirmation
                message = await websocket.recv()
                data = json.loads(message)
                
                if data.get('type') == 'connected':
                    self.session_id = data.get('session_id')
                    self.log("🆔", f"Received session ID: {self.session_id[:8]}...")
                
                # Subscribe to device updates
                subscribe_msg = {
                    'type': 'subscribe',
                    'device_id': self.device_id
                }
                await websocket.send(json.dumps(subscribe_msg))
                self.log("📡", f"Subscribed to device: {self.device_id[:8]}...")
                
                # Monitor messages
                self.log("👀", "Monitoring real-time updates... (Ctrl+C to stop)")
                self.log("💡", "TIP: In another terminal, control pistons to see updates!")
                print("")
                
                async for message in websocket:
                    self.message_count += 1
                    data = json.loads(message)
                    
                    msg_type = data.get('type')
                    
                    if msg_type == 'subscribed':
                        self.log("✅", "Subscription confirmed", data)
                    
                    elif msg_type == 'device_update':
                        device_id = data.get('device_id', 'unknown')[:8]
                        topic = data.get('topic', 'unknown')
                        payload = data.get('payload', {})
                        
                        # Parse the update
                        if 'status' in topic:
                            status = payload.get('status', 'unknown')
                            pistons = payload.get('pistons', {})
                            
                            self.log("📊", f"Device Status Update", {
                                'device': device_id + '...',
                                'status': status,
                                'pistons': pistons
                            })
                            
                            # Highlight active pistons
                            active = [k for k, v in pistons.items() if v == 'active']
                            if active:
                                print(f"         🔴 Active pistons: {', '.join(active)}")
                        
                        elif 'telemetry' in topic:
                            event_type = payload.get('event_type', 'unknown')
                            piston_num = payload.get('piston_number', '?')
                            
                            self.log("📈", f"Telemetry Event", {
                                'device': device_id + '...',
                                'event': event_type,
                                'piston': piston_num
                            })
                        
                        else:
                            self.log("📬", "Device Update", data)
                    
                    elif msg_type == 'pong':
                        elapsed = (datetime.now() - self.start_time).total_seconds()
                        self.log("🏓", f"Keepalive pong (uptime: {elapsed:.1f}s)")
                    
                    else:
                        self.log("📨", f"Message ({msg_type})", data)
                    
                    print("")
        
        except KeyboardInterrupt:
            self.log("👋", "Monitoring stopped by user")
            print("")
            self.log("📊", "Statistics:")
            print(f"         Messages received: {self.message_count}")
            print(f"         Uptime: {(datetime.now() - self.start_time).total_seconds():.1f}s")
        
        except websockets.exceptions.ConnectionClosed:
            self.log("❌", "Connection closed by server")
        
        except Exception as e:
            self.log("❌", f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 websocket_monitor.py <device_id>")
        print("Example: python3 websocket_monitor.py abc-123-def-456")
        sys.exit(1)
    
    device_id = sys.argv[1]
    ws_url = "ws://localhost:8080/ws"
    
    monitor = WebSocketMonitor(ws_url, device_id)
    asyncio.run(monitor.monitor())
