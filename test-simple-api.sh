#!/bin/bash

API="http://localhost:8080"

echo "🧪 Simple Backend API Test"
echo "=========================="

# Test 1: Health Check
echo -e "\n1️⃣ Health Check..."
curl -s --max-time 5 "$API/health"

# Test 2: Register User
echo -e "\n\n2️⃣ Registering user..."
REGISTER=$(curl -s --max-time 10 -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}')

echo "$REGISTER"

# Extract token (simple grep method)
TOKEN=$(echo "$REGISTER" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo -e "\n⚠️ Registration failed, trying login..."
    LOGIN=$(curl -s --max-time 10 -X POST "$API/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"email":"test@example.com","password":"password123"}')
    
    echo "$LOGIN"
    TOKEN=$(echo "$LOGIN" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
fi

if [ -z "$TOKEN" ]; then
    echo -e "\n❌ Authentication failed"
    exit 1
fi

echo -e "\n✅ Token received: ${TOKEN:0:50}..."

# Test 3: Create Device
echo -e "\n3️⃣ Creating device..."
CREATE=$(curl -s --max-time 10 -X POST "$API/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"My Test Device","mqtt_client_id":"raspberry-pi-001"}')

echo "$CREATE"

DEVICE_ID=$(echo "$CREATE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -z "$DEVICE_ID" ]; then
    echo -e "\n⚠️ Getting existing devices..."
    DEVICES=$(curl -s --max-time 10 "$API/devices" -H "Authorization: Bearer $TOKEN")
    echo "$DEVICES"
    DEVICE_ID=$(echo "$DEVICES" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)
fi

echo -e "\n✅ Device ID: $DEVICE_ID"

# Test 4: Get Devices
echo -e "\n4️⃣ Getting all devices..."
curl -s --max-time 10 "$API/devices" -H "Authorization: Bearer $TOKEN"

# Test 5: Activate Piston
echo -e "\n\n5️⃣ Activating piston #5..."
curl -s --max-time 10 -X POST "$API/devices/$DEVICE_ID/pistons/5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"activate","piston_number":5}'

# Test 6: Deactivate Piston
echo -e "\n\n6️⃣ Deactivating piston #5..."
curl -s --max-time 10 -X POST "$API/devices/$DEVICE_ID/pistons/5" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"deactivate","piston_number":5}'

echo -e "\n\n✅ All tests complete!"
