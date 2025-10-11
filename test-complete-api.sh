#!/bin/bash

API="http://localhost:8080"
TOKEN=""
DEVICE_ID=""

echo "🧪 Complete Backend API Test"
echo "============================"

# Test 1: Health Check
echo -e "\n1️⃣ Health Check..."
timeout 5 curl -s "$API/health" || echo '{"status":"timeout"}' | jq '.'

# Test 2: Register User
echo -e "\n2️⃣ Registering user..."
REGISTER_RESP=$(timeout 10 curl -s -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"testuser@example.com","password":"password123"}')

echo "$REGISTER_RESP" | jq '.'

TOKEN=$(echo "$REGISTER_RESP" | jq -r '.token // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ Registration failed - trying login instead..."
    
    # Try login if user already exists
    LOGIN_RESP=$(timeout 10 curl -s -X POST "$API/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"email":"testuser@example.com","password":"password123"}')
    
    echo "$LOGIN_RESP" | jq '.'
    TOKEN=$(echo "$LOGIN_RESP" | jq -r '.token // empty')
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ Authentication failed completely"
    exit 1
fi

echo "✅ Authenticated! Token: ${TOKEN:0:40}..."

# Test 3: Create Device
echo -e "\n3️⃣ Creating device..."
CREATE_RESP=$(timeout 10 curl -s -X POST "$API/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Raspberry Pi","mqtt_client_id":"raspberry-pi-001"}')

echo "$CREATE_RESP" | jq '.'

DEVICE_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
    echo "⚠️ Device creation might have failed or device already exists"
    
    # Get existing devices
    echo -e "\n   Getting existing devices..."
    DEVICES_RESP=$(timeout 10 curl -s -X GET "$API/devices" \
      -H "Authorization: Bearer $TOKEN")
    
    echo "$DEVICES_RESP" | jq '.'
    DEVICE_ID=$(echo "$DEVICES_RESP" | jq -r '.[0].id // empty')
fi

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
    echo "❌ No devices available"
    exit 1
fi

echo "✅ Device ID: $DEVICE_ID"

# Test 4: Get Devices List
echo -e "\n4️⃣ Getting devices list..."
timeout 10 curl -s -X GET "$API/devices" \
  -H "Authorization: Bearer $TOKEN" | jq '.'

# Test 5: Get Specific Device
echo -e "\n5️⃣ Getting device details..."
timeout 10 curl -s -X GET "$API/devices/$DEVICE_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.'

# Test 6: Control Piston (Activate)
echo -e "\n6️⃣ Activating piston #3..."
ACTIVATE_RESP=$(timeout 10 curl -s -X POST "$API/devices/$DEVICE_ID/pistons/3" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","piston_number":3}')

echo "$ACTIVATE_RESP" | jq '.'

# Test 7: Control Piston (Deactivate)
echo -e "\n7️⃣ Deactivating piston #3..."
timeout 10 curl -s -X POST "$API/devices/$DEVICE_ID/pistons/3" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"deactivate","piston_number":3}' | jq '.'

# Test 8: Get Telemetry
echo -e "\n8️⃣ Getting telemetry (last 10 events)..."
timeout 10 curl -s -X GET "$API/devices/$DEVICE_ID/telemetry?limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq '.'

echo -e "\n✅ All API tests complete!"
echo -e "\n📝 Summary:"
echo "   Token: ${TOKEN:0:40}..."
echo "   Device ID: $DEVICE_ID"
