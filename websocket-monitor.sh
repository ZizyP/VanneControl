#!/bin/bash

echo "🔌 WebSocket Real-Time Monitoring Demo"
echo "======================================="
echo ""
echo "WebSocket monitoring shows you:"
echo "  1. Real-time device status changes"
echo "  2. Piston state updates (active/inactive)"
echo "  3. Device connection/disconnection events"
echo "  4. MQTT message forwarding to web clients"
echo "  5. System latency and responsiveness"
echo ""
echo "Use Cases:"
echo "  • Live dashboards (see changes instantly)"
echo "  • Mobile apps (push notifications without polling)"
echo "  • System monitoring (detect failures immediately)"
echo "  • Multi-user collaboration (everyone sees same state)"
echo "  • Debugging (watch message flow in real-time)"
echo ""

# Check if websocat is installed
if command -v websocat &> /dev/null; then
    WS_CLIENT="websocat"
    echo "✅ Using websocat"
elif command -v wscat &> /dev/null; then
    WS_CLIENT="wscat"
    echo "✅ Using wscat"
else
    echo "⚠️  No WebSocket client found. Installing options:"
    echo ""
    echo "  Option 1 (websocat - recommended):"
    echo "    brew install websocat"
    echo "    # or"
    echo "    cargo install websocat"
    echo ""
    echo "  Option 2 (wscat):"
    echo "    npm install -g wscat"
    echo ""
    echo "  Option 3 (Python script below):"
    echo "    python3 websocket_monitor.py"
    echo ""
    WS_CLIENT="none"
fi

# Get device ID for testing
API="http://localhost:8080"
echo "Getting device ID for monitoring..."

LOGIN=$(curl -s -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@pistoncontrol.com","password":"admin123"}')

TOKEN=$(echo "$LOGIN" | jq -r '.token')
DEVICES=$(curl -s "$API/devices" -H "Authorization: Bearer $TOKEN")
DEVICE_ID=$(echo "$DEVICES" | jq -r '.[0].id // empty')

if [ -z "$DEVICE_ID" ]; then
    echo "⚠️  No devices found. Create one first:"
    echo "    curl -X POST $API/devices -H 'Authorization: Bearer $TOKEN' \\"
    echo "      -H 'Content-Type: application/json' \\"
    echo "      -d '{\"name\":\"Test Device\",\"mqtt_client_id\":\"test-001\"}'"
    exit 1
fi

echo "✅ Monitoring device: $DEVICE_ID"
echo ""

# Create Python WebSocket monitor
cat > websocket_monitor.py << 'EOMONITOR'
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
EOMONITOR

chmod +x websocket_monitor.py

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "THREE WAYS TO MONITOR WEBSOCKET"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$WS_CLIENT" = "websocat" ]; then
    echo "📱 Method 1: Interactive websocat (recommended)"
    echo "   Run in terminal 1:"
    echo "   websocat ws://localhost:8080/ws"
    echo ""
    echo "   Then send:"
    echo "   {\"type\":\"subscribe\",\"device_id\":\"$DEVICE_ID\"}"
    echo ""
elif [ "$WS_CLIENT" = "wscat" ]; then
    echo "📱 Method 1: Interactive wscat"
    echo "   Run in terminal 1:"
    echo "   wscat -c ws://localhost:8080/ws"
    echo ""
    echo "   Then send:"
    echo "   {\"type\":\"subscribe\",\"device_id\":\"$DEVICE_ID\"}"
    echo ""
fi

echo "🐍 Method 2: Python monitor script (best for learning)"
echo "   Terminal 1 (monitor):"
echo "   python3 websocket_monitor.py $DEVICE_ID"
echo ""
echo "   Terminal 2 (trigger events):"
echo "   curl -X POST $API/devices/$DEVICE_ID/pistons/3 \\"
echo "     -H 'Authorization: Bearer $TOKEN' \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"action\":\"activate\",\"piston_number\":3}'"
echo ""

echo "🌐 Method 3: Browser JavaScript console"
echo "   1. Open browser console (F12)"
echo "   2. Paste:"
cat << 'EOBROWSER'
const ws = new WebSocket('ws://localhost:8080/ws');
ws.onopen = () => console.log('✅ Connected');
ws.onmessage = (e) => {
  const data = JSON.parse(e.data);
  console.log('📨', data);
  if (data.type === 'connected') {
    ws.send(JSON.stringify({
      type: 'subscribe',
      device_id: 'YOUR_DEVICE_ID'
    }));
  }
};
ws.onerror = (e) => console.error('❌', e);
EOBROWSER
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "WHAT YOU'LL SEE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣ Connection Message:"
echo '   {"type":"connected","session_id":"uuid-here"}'
echo ""
echo "2️⃣ Subscription Confirmation:"
echo '   {"type":"subscribed","device_id":"device-uuid"}'
echo ""
echo "3️⃣ Real-Time Device Updates (when piston activated):"
echo '   {'
echo '     "type":"device_update",'
echo '     "device_id":"device-uuid",'
echo '     "topic":"devices/device-uuid/status",'
echo '     "payload":{"status":"online","pistons":{"3":"active"}},'
echo '     "timestamp":1697123456789'
echo '   }'
echo ""
echo "4️⃣ Keepalive (every 30 seconds):"
echo '   Send: {"type":"ping"}'
echo '   Receive: {"type":"pong"}'
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TRY IT NOW!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ -f websocket_monitor.py ]; then
    read -p "▶️  Start Python monitor now? (yes/no): " start_monitor
    if [ "$start_monitor" = "yes" ]; then
        echo ""
        echo "Starting WebSocket monitor..."
        echo "In another terminal, control pistons to see updates!"
        echo ""
        python3 websocket_monitor.py "$DEVICE_ID"
    fi
fi
