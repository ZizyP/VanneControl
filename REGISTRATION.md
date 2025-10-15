# 🎯 Production-Ready User & Device Registration Flow

## Overview

This document describes how users create accounts and register devices in a production environment.

---

## 📱 User Registration Flow (Mobile App)

### Step 1: User Creates Account

**Mobile App Screen:**
```
┌─────────────────────────────┐
│     Create Account          │
├─────────────────────────────┤
│ Email: [____________]       │
│ Password: [____________]    │
│ Confirm: [____________]     │
│                             │
│ [  Create Account  ]        │
└─────────────────────────────┘
```

**API Call:**
```http
POST /auth/register
Content-Type: application/json

{
  "email": "john@factory.com",
  "password": "SecurePass123!"
}
```

**Response:**
```json
{
  "token": "eyJhbGci...",
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "john@factory.com",
    "role": "user"
  }
}
```

**Mobile App Actions:**
- ✅ Save token securely (Keychain/KeyStore)
- ✅ Navigate to device setup screen
- ✅ Show welcome message

---

## 🔧 Device Registration Flow

### Option A: QR Code Pairing (Recommended)

**Physical Device (Raspberry Pi):**
1. Device generates unique pairing code on first boot
2. Displays QR code on connected screen OR
3. Prints pairing code on receipt printer OR
4. Shows code on LED display

**Mobile App:**
1. User clicks "Add Device"
2. Camera opens for QR code scanning
3. Scans device's QR code
4. App sends pairing request to backend

**QR Code Contains:**
```json
{
  "device_id": "RPI-A1-20241013-001",
  "pairing_code": "ABCD-1234-EFGH",
  "device_type": "pneumatic_controller_8ch"
}
```

**API Call:**
```http
POST /devices/pair
Authorization: Bearer {token}
Content-Type: application/json

{
  "device_id": "RPI-A1-20241013-001",
  "pairing_code": "ABCD-1234-EFGH",
  "device_name": "Production Line A"
}
```

---

### Option B: Manual Entry

**Mobile App Screen:**
```
┌─────────────────────────────┐
│     Add Device              │
├─────────────────────────────┤
│ Device Name:                │
│ [Production Line A____]     │
│                             │
│ Device ID (from sticker):   │
│ [RPI-A1-20241013-001__]     │
│                             │
│ Pairing Code (8 digits):    │
│ [____-____]                 │
│                             │
│ [  Add Device  ]            │
└─────────────────────────────┘
```

---

### Option C: Automatic Discovery (Advanced)

**Device broadcasts on local network:**
- mDNS/Bonjour service
- User on same WiFi sees available devices
- One-click pairing

---

## 🏭 Device ID Generation Strategy

### Format: `{PREFIX}-{LOCATION}-{DATE}-{COUNTER}`

**Examples:**
```
RPI-A1-20241013-001    (Raspberry Pi, Area A1, Oct 13 2024, device #1)
RPI-B2-20241013-002    (Raspberry Pi, Area B2, Oct 13 2024, device #2)
ESP-C3-20241013-001    (ESP32, Area C3, Oct 13 2024, device #1)
```

**Benefits:**
- ✅ Human-readable
- ✅ Indicates location
- ✅ Shows installation date
- ✅ Easy to reference in support calls
- ✅ No collisions (date + counter)

**Alternative: MAC Address Based**
```
Device ID: RPI-B827EB123456
(Uses last 6 bytes of MAC address)
```

---

## 🔐 Pairing Code Security

**Generation (on Raspberry Pi):**
```python
import secrets
import string

def generate_pairing_code():
    """Generate secure 8-character pairing code"""
    chars = string.ascii_uppercase + string.digits
    # Remove confusing characters: 0, O, 1, I
    chars = chars.replace('0', '').replace('O', '').replace('1', '').replace('I', '')
    code = ''.join(secrets.choice(chars) for _ in range(8))
    return f"{code[:4]}-{code[4:]}"  # Format: ABCD-1234

# Example output: "A7K9-M3P2"
```

**Validation:**
- Code expires after 24 hours
- Can only be used once
- Must match device's stored code
- Rate limited (5 attempts per hour)

---

## 🎨 Complete Registration Flow (Backend)

### Update DeviceRoutes.kt

Add new pairing endpoint:

```kotlin
@Serializable
data class DevicePairingRequest(
    val device_id: String,
    val pairing_code: String,
    val device_name: String
)

@Serializable
data class DevicePairingResponse(
    val success: Boolean,
    val device: DeviceResponse?,
    val error: String? = null
)

// New endpoint for pairing
post("/devices/pair") {
    val request = call.receive<DevicePairingRequest>()
    val principal = call.principal<JWTPrincipal>()!!
    val userId = UUID.fromString(principal.payload.getClaim("userId").asString())
    
    // Verify pairing code with device (via MQTT or database)
    val isValidCode = verifyPairingCode(request.device_id, request.pairing_code)
    
    if (!isValidCode) {
        return@post call.respond(HttpStatusCode.Unauthorized, 
            DevicePairingResponse(
                success = false,
                device = null,
                error = "Invalid pairing code"
            ))
    }
    
    // Check if device already registered
    val existingDevice = dbQuery {
        Devices.select { Devices.mqttClientId eq request.device_id }
            .singleOrNull()
    }
    
    if (existingDevice != null) {
        return@post call.respond(HttpStatusCode.Conflict,
            DevicePairingResponse(
                success = false,
                device = null,
                error = "Device already registered"
            ))
    }
    
    // Create device
    val deviceId = UUID.randomUUID()
    
    dbQuery {
        Devices.insert {
            it[id] = deviceId
            it[name] = request.device_name
            it[ownerId] = userId
            it[mqttClientId] = request.device_id
            it[status] = "offline"
            it[createdAt] = Instant.now()
            it[updatedAt] = Instant.now()
        }
        
        // Create 8 pistons
        for (pistonNum in 1..8) {
            Pistons.insert {
                it[id] = UUID.randomUUID()
                it[Pistons.deviceId] = deviceId
                it[pistonNumber] = pistonNum
                it[state] = "inactive"
                it[lastTriggered] = null
            }
        }
    }
    
    // Notify device via MQTT that it's been paired
    mqttManager.publishCommand(request.device_id, """
        {"type":"paired","owner_id":"$userId","device_uuid":"$deviceId"}
    """)
    
    logger.info { "Device paired: $request.device_id to user $userId" }
    
    // Return device with pistons
    val pistons = dbQuery {
        Pistons.select { Pistons.deviceId eq deviceId }
            .map { row ->
                PistonResponse(
                    id = row[Pistons.id].toString(),
                    piston_number = row[Pistons.pistonNumber],
                    state = row[Pistons.state],
                    last_triggered = row[Pistons.lastTriggered]?.toString()
                )
            }
    }
    
    call.respond(HttpStatusCode.Created, DevicePairingResponse(
        success = true,
        device = DeviceResponse(
            id = deviceId.toString(),
            name = request.device_name,
            status = "offline",
            pistons = pistons
        )
    ))
}
```

---

## 📋 Device Sticker/Label Design

**Physical label on each Raspberry Pi:**

```
┌────────────────────────────┐
│   PISTON CONTROLLER        │
│   Model: PC-8CH-V1         │
├────────────────────────────┤
│                            │
│   [QR CODE]                │
│                            │
├────────────────────────────┤
│ Device ID:                 │
│ RPI-A1-20241013-001        │
│                            │
│ Pairing Code:              │
│ ABCD-1234                  │
│                            │
│ Support: support@...       │
└────────────────────────────┘
```

---

## 🔄 Complete User Journey

### Day 1: Installation

**Factory Manager (John):**
1. Downloads mobile app from App Store
2. Creates account: john@factory.com
3. Receives email verification (optional)
4. Logs into app

**Technician installs Raspberry Pi:**
1. Mounts Raspberry Pi on production line
2. Connects to power and network
3. Device boots up, generates pairing code
4. Shows code on screen/LED

**John pairs device:**
1. Opens app → "Add Device"
2. Scans QR code on device
3. Names it: "Production Line A"
4. Device appears in app
5. All 8 pistons shown as "inactive"

### Day 2: Daily Use

**Operator (Maria):**
1. Opens app
2. Sees "Production Line A" status: Online
3. Needs to activate piston #3
4. Taps piston #3 → "Activate"
5. Instantly sees green indicator
6. Physical piston activates
7. WebSocket shows update to all connected users

### Day 30: Adding More Devices

**John adds second line:**
1. Opens app → "Add Device"
2. Scans new Raspberry Pi
3. Names it: "Production Line B"
4. Now controls 2 lines from one app

---

## 🎯 Key Differences from Current Setup

| Current (Testing) | Production |
|------------------|------------|
| Hardcoded device ID | Generated on device |
| Manual device creation | QR code pairing |
| UUID in API calls | Human-readable IDs |
| Test accounts | Real user registration |
| No pairing validation | Secure pairing codes |
| Direct MQTT client ID | Pairing flow |

---

## 📱 Mobile App Screens Needed

### 1. Registration Screen
- Email input
- Password input
- Create account button
- Link to login

### 2. Login Screen
- Email input
- Password input
- Login button
- Forgot password link

### 3. Device List Screen
- List of user's devices
- Status indicator (online/offline)
- Add device button
- Settings button

### 4. Add Device Screen
- QR code scanner
- Manual entry option
- Help/instructions

### 5. Device Control Screen
- Device name
- 8 piston controls
- Status information
- Telemetry/history button

### 6. Settings Screen
- User profile
- Logout
- About/version
- Support contact

---

## 🔧 Next Steps

1. **Reset database** ✅ (run reset-database.sh)
2. **Update backend** - Add pairing endpoint
3. **Update Raspberry Pi** - Generate device ID and pairing code
4. **Build mobile app** - Implement registration and pairing flows
5. **Test end-to-end** - Real user creates account → pairs device → controls pistons

---

## 💡 Bonus Features

### Device Sharing
```http
POST /devices/{device_id}/share
{
  "email": "operator@factory.com",
  "permission": "control"  // or "view_only"
}
```

### Device Groups
```http
POST /groups
{
  "name": "Production Floor",
  "device_ids": ["dev1", "dev2", "dev3"]
}
```

### Bulk Control
```http
POST /groups/{group_id}/pistons/activate
{
  "piston_numbers": [1, 3, 5]
}
```

This is how a production IoT system should work! 🏭✨
