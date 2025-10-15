#!/bin/bash

API="http://localhost:8080"
TOKEN=""
DEVICE_ID=""

echo "🧪 Complete Backend API Test"
echo "============================"

# Test 1: Health Check
echo -e "\n1️⃣ Health Check..."
RESP=$(timeout 5 curl -s "$API/health" 2>/dev/null)
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "❌ Backend is not responding (connection failed)"
  echo "   Make sure services are running: docker compose up -d"
  exit 1
fi

if [ -z "$RESP" ]; then
  echo "❌ Backend returned empty response"
  exit 1
fi

echo "$RESP" | jq '.' 2>/dev/null || {
  echo "❌ Invalid JSON response: $RESP"
  exit 1
}

# Verify the response contains expected health check data
if echo "$RESP" | jq -e '.status' > /dev/null 2>&1; then
  echo "✅ Health check passed"
else
  echo "❌ Health check response missing 'status' field"
  exit 1
fi

# Test 2: Register User
echo -e "\n2️⃣ Registering user..."
REGISTER_RESP=$(timeout 10 curl -s -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@pistoncontrol.com","password":"admin123"}' 2>/dev/null)

if [ -z "$REGISTER_RESP" ]; then
  echo "❌ Registration endpoint not responding"
  exit 1
fi

echo "$REGISTER_RESP" | jq '.'

TOKEN=$(echo "$REGISTER_RESP" | jq -r '.token // empty')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ Registration failed - trying login instead..."
    
    # Try login if user already exists
    LOGIN_RESP=$(timeout 10 curl -s -X POST "$API/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"email":"admin@pistoncontrol.com","password":"admin123"}' 2>/dev/null)
    
    if [ -z "$LOGIN_RESP" ]; then
      echo "❌ Login endpoint not responding"
      exit 1
    fi
    
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
  -d '{"name":"Test Raspberry Pi","mqtt_client_id":"raspberry-pi-001"}' 2>/dev/null)

if [ -z "$CREATE_RESP" ]; then
  echo "❌ Device creation endpoint not responding"
  exit 1
fi

echo "$CREATE_RESP" | jq '.'

DEVICE_ID=$(echo "$CREATE_RESP" | jq -r '.id // empty')

if [ -z "$DEVICE_ID" ] || [ "$DEVICE_ID" = "null" ]; then
    echo "⚠️ Device creation might have failed or device already exists"
    
    # Get existing devices
    echo -e "\n   Getting existing devices..."
    DEVICES_RESP=$(timeout 10 curl -s -X GET "$API/devices" \
      -H "Authorization: Bearer $TOKEN" 2>/dev/null)
    
    if [ -z "$DEVICES_RESP" ]; then
      echo "❌ Devices endpoint not responding"
      exit 1
    fi
    
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
DEVICES_LIST=$(timeout 10 curl -s -X GET "$API/devices" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if [ -z "$DEVICES_LIST" ]; then
  echo "❌ Get devices endpoint not responding"
  exit 1
fi

echo "$DEVICES_LIST" | jq '.'

# Test 5: Get Specific Device
echo -e "\n5️⃣ Getting device details..."
DEVICE_DETAILS=$(timeout 10 curl -s -X GET "$API/devices/$DEVICE_ID" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if [ -z "$DEVICE_DETAILS" ]; then
  echo "❌ Get device details endpoint not responding"
  exit 1
fi

echo "$DEVICE_DETAILS" | jq '.'

# Test 6: Control Piston (Activate)
echo -e "\n6️⃣ Activating piston #3..."
ACTIVATE_RESP=$(timeout 10 curl -s -X POST "$API/devices/$DEVICE_ID/pistons/3" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","piston_number":3}' 2>/dev/null)

if [ -z "$ACTIVATE_RESP" ]; then
  echo "❌ Activate piston endpoint not responding"
  exit 1
fi

echo "$ACTIVATE_RESP" | jq '.'

# Test 7: Control Piston (Deactivate)
echo -e "\n7️⃣ Deactivating piston #3..."
DEACTIVATE_RESP=$(timeout 10 curl -s -X POST "$API/devices/$DEVICE_ID/pistons/3" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"deactivate","piston_number":3}' 2>/dev/null)

if [ -z "$DEACTIVATE_RESP" ]; then
  echo "❌ Deactivate piston endpoint not responding"
  exit 1
fi

echo "$DEACTIVATE_RESP" | jq '.'

# Test 8: Get Telemetry
echo -e "\n8️⃣ Getting telemetry (last 10 events)..."
TELEMETRY=$(timeout 10 curl -s -X GET "$API/devices/$DEVICE_ID/telemetry?limit=10" \
  -H "Authorization: Bearer $TOKEN" 2>/dev/null)

if [ -z "$TELEMETRY" ]; then
  echo "❌ Telemetry endpoint not responding"
  exit 1
fi

echo "$TELEMETRY" | jq '.'

echo -e "\n✅ All API tests complete!"
echo -e "\n📝 Summary:"
echo "   Token: ${TOKEN:0:40}..."
echo "   Device ID: $DEVICE_ID"
