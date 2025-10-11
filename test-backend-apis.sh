#!/bin/bash

API="http://localhost:8080"
TOKEN=""

echo "🧪 Testing Backend APIs"
echo "======================"

# 1. Register
echo -e "\n1️⃣  Registering user..."
REGISTER_RESP=$(curl -s -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"testuser@example.com","password":"password123"}')

echo "$REGISTER_RESP"
TOKEN=$(echo "$REGISTER_RESP" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "❌ Registration failed"
    exit 1
fi

echo "✅ Token: ${TOKEN:0:30}..."

# 2. Create Device
echo -e "\n2️⃣  Creating device..."
CREATE_DEVICE=$(curl -s -X POST "$API/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Pi","mqtt_client_id":"raspberry-pi-001"}')

echo "$CREATE_DEVICE"
DEVICE_ID=$(echo "$CREATE_DEVICE" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

echo "✅ Device ID: $DEVICE_ID"

# 3. Get Devices
echo -e "\n3️⃣  Getting devices..."
curl -s -X GET "$API/devices" \
  -H "Authorization: Bearer $TOKEN"

# 4. Control Piston
echo -e "\n\n4️⃣  Activating piston #5..."
curl -s -X POST "$API/devices/$DEVICE_ID/pistons/5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","piston_number":5}'

echo -e "\n\n✅ All tests complete!"
