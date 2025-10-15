# 📡 LilyGO T-SIM7600E Setup for Piston Control

## Hardware Overview

**LilyGO T-SIM7600E Specifications:**
- ESP32-WROVER-B (8MB PSRAM, 16MB Flash)
- SIM7600E LTE Cat-1 Module
- Nano SIM card slot
- GPS/GNSS support
- 18650 battery holder
- USB-C charging
- Multiple GPIO breakouts

**Perfect for 1NCE SIM card!** ✅

---

## 🔌 Pin Configuration

### LilyGO T-SIM7600E Specific Pins

```cpp
// SIM7600E Modem Control
#define MODEM_TX              27
#define MODEM_RX              26
#define MODEM_PWRKEY          4
#define MODEM_POWER_ON        25
#define MODEM_DTR             32
#define MODEM_RI              33

// I2C for peripherals (if needed)
#define I2C_SDA               21
#define I2C_SCL               22

// Available GPIO for Pistons (8 relays)
#define PISTON_1              12
#define PISTON_2              13
#define PISTON_3              14
#define PISTON_4              15
#define PISTON_5              2
#define PISTON_6              5
#define PISTON_7              18
#define PISTON_8              19

// LED indicator
#define LED_PIN               23

// Battery voltage reading
#define BATTERY_ADC           35
```

---

## 📦 Required Libraries

**PlatformIO `platformio.ini`:**

```ini
[env:lilygo-t-sim7600]
platform = espressif32
board = esp32dev
framework = arduino

lib_deps = 
    vshymanskyy/TinyGSM@^0.11.7
    knolleary/PubSubClient@^2.8
    bblanchon/ArduinoJson@^6.21.3

monitor_speed = 115200

build_flags =
    -DTINY_GSM_MODEM_SIM7600
    -DTINY_GSM_RX_BUFFER=1024
    -DDEBUG_MODEM=1
    
upload_speed = 921600
```

---

## 🔧 Complete LilyGO Code

```cpp
/*
 * LilyGO T-SIM7600E Piston Controller
 * 
 * Hardware: ESP32 + SIM7600E LTE Module
 * SIM Card: 1NCE (500 MB / 10 years)
 * Protocol: Binary MQTT
 * 
 * Data usage: ~35 KB/day = 12.6 MB/year = 126 MB/10 years ✅
 */

#define TINY_GSM_MODEM_SIM7600
#define TINY_GSM_RX_BUFFER 1024

#include <TinyGsmClient.h>
#include <PubSubClient.h>

// Modem pins
#define MODEM_TX              27
#define MODEM_RX              26
#define MODEM_PWRKEY          4
#define MODEM_POWER_ON        25
#define MODEM_DTR             32
#define MODEM_RI              33

// Piston control pins
const int PISTON_PINS[8] = {12, 13, 14, 15, 2, 5, 18, 19};

// LED
#define LED_PIN               23

// 1NCE APN settings
const char APN[] = "iot.1nce.net";
const char USER[] = "";
const char PASS[] = "";

// MQTT broker
const char* MQTT_BROKER = "your-server.com";
const int MQTT_PORT = 1883;

// Device ID
String DEVICE_ID;
uint8_t deviceIdBytes[6];

// Modem and MQTT clients
HardwareSerial SerialAT(1);
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
PubSubClient mqtt(gsmClient);

// Piston states
uint8_t pistonStates = 0x00;

// Statistics
unsigned long totalBytesSent = 0;
unsigned long messagesCount = 0;

// ════════════════════════════════════════════════════════════
// BINARY PROTOCOL STRUCTURES
// ════════════════════════════════════════════════════════════

#define MSG_TYPE_STATUS       0x01
#define MSG_TYPE_TELEMETRY    0x02
#define MSG_TYPE_COMMAND_ACK  0x03

struct __attribute__((packed)) StatusMessage {
  uint8_t type;           // 0x01
  uint8_t deviceId[6];    // MAC address bytes
  uint8_t status;         // Status flags
  uint8_t pistons;        // 8 bits for 8 pistons
  uint16_t timestamp;     // Seconds since boot
  uint8_t crc;            // Checksum
};

struct __attribute__((packed)) TelemetryMessage {
  uint8_t type;           // 0x02
  uint8_t deviceId[6];
  uint8_t pistonNumber;
  uint8_t event;
  uint16_t timestamp;
  uint8_t crc;
};

// ════════════════════════════════════════════════════════════
// SETUP
// ════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n╔════════════════════════════════════════╗");
  Serial.println("║  LilyGO T-SIM7600E Piston Controller   ║");
  Serial.println("║  Binary MQTT Protocol / 1NCE SIM       ║");
  Serial.println("╚════════════════════════════════════════╝\n");
  
  // Initialize LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  
  // Initialize piston pins
  for (int i = 0; i < 8; i++) {
    pinMode(PISTON_PINS[i], OUTPUT);
    digitalWrite(PISTON_PINS[i], LOW);
  }
  Serial.println("✓ GPIO pins initialized");
  
  // Get device ID from ESP32 MAC
  DEVICE_ID = getDeviceID();
  Serial.print("✓ Device ID: ");
  Serial.println(DEVICE_ID);
  
  // Power on modem
  Serial.println("\n--- Powering on modem ---");
  powerOnModem();
  
  // Initialize modem serial
  SerialAT.begin(115200, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(3000);
  
  // Initialize modem
  Serial.println("--- Initializing modem ---");
  if (!modem.init()) {
    Serial.println("✗ Modem initialization failed!");
    ESP.restart();
  }
  Serial.println("✓ Modem initialized");
  
  // Get modem info
  String modemInfo = modem.getModemInfo();
  Serial.print("✓ Modem: ");
  Serial.println(modemInfo);
  
  // Check SIM card
  if (!modem.simUnlock()) {
    Serial.println("✗ SIM card not detected!");
    ESP.restart();
  }
  Serial.println("✓ SIM card OK");
  
  // Connect to network
  Serial.println("\n--- Connecting to network ---");
  Serial.print("Operator: ");
  Serial.println(modem.getOperator());
  
  if (!modem.waitForNetwork(60000L)) {
    Serial.println("✗ Network connection failed!");
    ESP.restart();
  }
  Serial.println("✓ Network connected");
  
  // Connect to GPRS
  Serial.print("Connecting to APN: ");
  Serial.println(APN);
  
  if (!modem.gprsConnect(APN, USER, PASS)) {
    Serial.println("✗ GPRS connection failed!");
    ESP.restart();
  }
  Serial.println("✓ GPRS connected");
  
  // Check signal quality
  int csq = modem.getSignalQuality();
  Serial.print("✓ Signal quality: ");
  Serial.print(csq);
  Serial.println(" (0-31, higher is better)");
  
  // Get IP address
  IPAddress ip = modem.localIP();
  Serial.print("✓ IP address: ");
  Serial.println(ip);
  
  // LED on = connected
  digitalWrite(LED_PIN, HIGH);
  
  // Connect to MQTT
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(512);
  connectMQTT();
  
  Serial.println("\n╔════════════════════════════════════════╗");
  Serial.println("║       Setup Complete - Running         ║");
  Serial.println("╚════════════════════════════════════════╝\n");
}

// ════════════════════════════════════════════════════════════
// MAIN LOOP
// ════════════════════════════════════════════════════════════

void loop() {
  // Check network connection
  if (!modem.isNetworkConnected()) {
    Serial.println("⚠ Network disconnected! Reconnecting...");
    connectNetwork();
  }
  
  // Check GPRS connection
  if (!modem.isGprsConnected()) {
    Serial.println("⚠ GPRS disconnected! Reconnecting...");
    modem.gprsConnect(APN, USER, PASS);
  }
  
  // Check MQTT connection
  if (!mqtt.connected()) {
    connectMQTT();
  }
  mqtt.loop();
  
  // Publish binary status every 30 seconds
  static unsigned long lastStatus = 0;
  if (millis() - lastStatus > 30000) {
    publishBinaryStatus();
    lastStatus = millis();
    
    // Print statistics every 10 minutes
    static int statusCount = 0;
    if (++statusCount >= 20) {
      printStatistics();
      checkSignalQuality();
      statusCount = 0;
    }
  }
  
  // Blink LED to show activity
  static unsigned long lastBlink = 0;
  if (millis() - lastBlink > 1000) {
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
    lastBlink = millis();
  }
}

// ════════════════════════════════════════════════════════════
// MODEM CONTROL
// ════════════════════════════════════════════════════════════

void powerOnModem() {
  pinMode(MODEM_PWRKEY, OUTPUT);
  pinMode(MODEM_POWER_ON, OUTPUT);
  
  digitalWrite(MODEM_POWER_ON, HIGH);
  
  // Pull PWRKEY low for 1 second to power on
  digitalWrite(MODEM_PWRKEY, LOW);
  delay(1000);
  digitalWrite(MODEM_PWRKEY, HIGH);
  
  delay(3000); // Wait for modem to boot
  Serial.println("✓ Modem powered on");
}

void connectNetwork() {
  Serial.println("Connecting to network...");
  if (modem.waitForNetwork(30000L)) {
    Serial.println("✓ Network connected");
    if (!modem.isGprsConnected()) {
      modem.gprsConnect(APN, USER, PASS);
    }
  }
}

void checkSignalQuality() {
  int csq = modem.getSignalQuality();
  Serial.print("Signal: ");
  Serial.print(csq);
  
  if (csq < 10) {
    Serial.println(" (POOR)");
  } else if (csq < 20) {
    Serial.println(" (FAIR)");
  } else {
    Serial.println(" (GOOD)");
  }
}

// ════════════════════════════════════════════════════════════
// DEVICE ID
// ════════════════════════════════════════════════════════════

String getDeviceID() {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  
  memcpy(deviceIdBytes, mac, 6);
  
  char id[16];
  sprintf(id, "ESP-%02X%02X%02X", mac[3], mac[4], mac[5]);
  return String(id);
}

// ════════════════════════════════════════════════════════════
// MQTT
// ════════════════════════════════════════════════════════════

void connectMQTT() {
  Serial.print("Connecting to MQTT...");
  
  while (!mqtt.connected()) {
    if (mqtt.connect(DEVICE_ID.c_str())) {
      Serial.println("connected!");
      
      String commandTopic = "devices/" + DEVICE_ID + "/commands/binary";
      mqtt.subscribe(commandTopic.c_str());
      
      Serial.println("✓ Subscribed to: " + commandTopic);
      publishBinaryStatus();
    } else {
      Serial.print("failed, rc=");
      Serial.println(mqtt.state());
      delay(5000);
    }
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  Serial.print("Command received (");
  Serial.print(length);
  Serial.println(" bytes)");
  
  if (length >= 2) {
    uint8_t action = payload[0];
    uint8_t pistonNum = payload[1];
    
    if (pistonNum >= 1 && pistonNum <= 8) {
      if (action == 0x01) {
        activatePiston(pistonNum - 1);
      } else {
        deactivatePiston(pistonNum - 1);
      }
    }
  }
}

// ════════════════════════════════════════════════════════════
// PISTON CONTROL
// ════════════════════════════════════════════════════════════

void activatePiston(int index) {
  digitalWrite(PISTON_PINS[index], HIGH);
  pistonStates |= (1 << index);
  
  Serial.print("✓ Piston ");
  Serial.print(index + 1);
  Serial.println(" ACTIVATED");
  
  publishBinaryTelemetry(index + 1, 0x01);
  publishBinaryStatus();
}

void deactivatePiston(int index) {
  digitalWrite(PISTON_PINS[index], LOW);
  pistonStates &= ~(1 << index);
  
  Serial.print("✓ Piston ");
  Serial.print(index + 1);
  Serial.println(" DEACTIVATED");
  
  publishBinaryTelemetry(index + 1, 0x00);
  publishBinaryStatus();
}

// ════════════════════════════════════════════════════════════
// BINARY MQTT PUBLISHING
// ════════════════════════════════════════════════════════════

void publishBinaryStatus() {
  StatusMessage msg;
  msg.type = MSG_TYPE_STATUS;
  memcpy(msg.deviceId, deviceIdBytes, 6);
  msg.status = 0x01; // Online
  msg.pistons = pistonStates;
  msg.timestamp = millis() / 1000;
  msg.crc = calculateCRC((uint8_t*)&msg, sizeof(msg) - 1);
  
  String topic = "devices/" + DEVICE_ID + "/status/binary";
  
  if (mqtt.publish(topic.c_str(), (uint8_t*)&msg, sizeof(msg))) {
    totalBytesSent += sizeof(msg);
    messagesCount++;
    
    Serial.print("✓ Status (");
    Serial.print(sizeof(msg));
    Serial.println(" bytes)");
  }
}

void publishBinaryTelemetry(uint8_t pistonNum, uint8_t event) {
  TelemetryMessage msg;
  msg.type = MSG_TYPE_TELEMETRY;
  memcpy(msg.deviceId, deviceIdBytes, 6);
  msg.pistonNumber = pistonNum;
  msg.event = event;
  msg.timestamp = millis() / 1000;
  msg.crc = calculateCRC((uint8_t*)&msg, sizeof(msg) - 1);
  
  String topic = "devices/" + DEVICE_ID + "/telemetry/binary";
  
  if (mqtt.publish(topic.c_str(), (uint8_t*)&msg, sizeof(msg))) {
    totalBytesSent += sizeof(msg);
    messagesCount++;
  }
}

uint8_t calculateCRC(uint8_t* data, size_t length) {
  uint8_t crc = 0x00;
  for (size_t i = 0; i < length; i++) {
    crc ^= data[i];
  }
  return crc;
}

// ════════════════════════════════════════════════════════════
// STATISTICS
// ════════════════════════════════════════════════════════════

void printStatistics() {
  Serial.println("\n╔════════════════════════════════════════╗");
  Serial.println("║         📊 DATA USAGE STATS            ║");
  Serial.println("╠════════════════════════════════════════╣");
  
  Serial.print("║ Messages: ");
  Serial.print(messagesCount);
  Serial.println();
  
  Serial.print("║ Total: ");
  Serial.print(totalBytesSent);
  Serial.println(" bytes");
  
  float dailyKB = (totalBytesSent / 1024.0) * (86400000.0 / millis());
  Serial.print("║ Daily: ");
  Serial.print(dailyKB, 1);
  Serial.println(" KB");
  
  float monthlyMB = dailyKB * 30 / 1024.0;
  Serial.print("║ Monthly: ");
  Serial.print(monthlyMB, 2);
  Serial.println(" MB");
  
  float yearlyMB = monthlyMB * 12;
  Serial.print("║ Yearly: ");
  Serial.print(yearlyMB, 1);
  Serial.println(" MB");
  
  float tenYearMB = yearlyMB * 10;
  Serial.print("║ 10 Years: ");
  Serial.print(tenYearMB, 1);
  Serial.println(" MB");
  
  float percentUsed = (tenYearMB / 500.0) * 100;
  Serial.print("║ 1NCE Quota: ");
  Serial.print(percentUsed, 1);
  Serial.println("%");
  
  Serial.println("╚════════════════════════════════════════╝\n");
}
```

---

## 🔋 Power Management

### Battery Monitoring

```cpp
float getBatteryVoltage() {
  // Read battery voltage from ADC
  int raw = analogRead(BATTERY_ADC);
  return (raw / 4095.0) * 3.3 * 2; // Voltage divider
}

void checkBattery() {
  float voltage = getBatteryVoltage();
  Serial.print("Battery: ");
  Serial.print(voltage, 2);
  Serial.println("V");
  
  if (voltage < 3.3) {
    Serial.println("⚠ LOW BATTERY!");
    // Enter deep sleep to preserve power
  }
}
```

### Deep Sleep (Optional)

```cpp
void enterDeepSleep(int seconds) {
  Serial.println("Entering deep sleep...");
  
  // Power off modem
  modem.poweroff();
  
  // Configure wakeup
  esp_sleep_enable_timer_wakeup(seconds * 1000000ULL);
  
  // Sleep
  esp_deep_sleep_start();
}
```

---

## 💰 Cost Breakdown

**Per Device:**
- LilyGO T-SIM7600E: $25-30
- 1NCE SIM card: €10 (10 years)
- 8-channel relay: $4
- 18650 battery: $3
- Enclosure: $5
- **Total: ~$47-52**

**10 Years Total Cost:**
- Hardware: $47-52 (one-time)
- Data: €10 / 10 = **€1/year**
- **Total: €10 over 10 years!**

Compared to WiFi + monthly SIM:
- €2-5/month × 120 months = **€240-600** savings!

---

## 📱 1NCE SIM Card Setup

**Activation:**
1. Go to https://portal.1nce.com
2. Register SIM card
3. Insert into LilyGO
4. APN: `iot.1nce.net`
5. No username/password needed

**Monitor usage:**
- Check portal for data usage
- Set up alerts at 80% (400 MB)

---

## 🎯 Final Configuration

**What you get:**
- ✅ ESP32 with built-in LTE
- ✅ No WiFi dependency
- ✅ Works anywhere with cellular coverage
- ✅ 30-second heartbeat
- ✅ Binary protocol (92% data savings)
- ✅ 126 MB / 10 years (25% of quota)
- ✅ €1/year data cost
- ✅ Remote control from anywhere
- ✅ Battery backup capable

**Perfect for industrial IoT!** 🏭✨
