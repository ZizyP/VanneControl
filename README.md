# 🔧 IoT Piston Control System

A complete self-hosted IoT solution for remotely controlling piston actuators via MQTT. Built with modern technologies for reliability and scalability.

## ✨ Features

- 🔐 **Secure Authentication** - JWT-based user authentication with password hashing
- 🌐 **REST API** - Full-featured API for device management
- 📡 **MQTT Communication** - Real-time device control via Mosquitto broker
- 🔌 **WebSocket Support** - Live status updates to mobile/web clients
- 📊 **PostgreSQL Database** - Persistent storage for users, devices, and telemetry
- 🐳 **Docker Compose** - One-command deployment
- 📱 **Android Mobile App** - Native Android application with real-time monitoring
- 🍓 **Hardware Support** - Raspberry Pi and ESP32 compatible
- 📈 **Statistics & Analytics** - Historical data tracking and visualization
- 🔔 **Real-time Updates** - WebSocket-based live device status monitoring

## 🏗️ Architecture
```
Android App (Kotlin) ←→ Nginx ←→ Ktor Backend ←→ PostgreSQL
        ↓ WebSocket           ↓ REST API
        └─────────────────────┘
                              ↓
                        Mosquitto MQTT
                              ↓
                          ESP32/IoT Devices
```

### System Components

- **Android Mobile App** (`piston-control-mobile/MyApplicationV10/`)
  - Native Android app built with Kotlin
  - MVVM architecture with Coroutines
  - Real-time WebSocket integration
  - Material Design UI

- **Backend Server** (`backend/`)
  - Ktor framework (Kotlin)
  - REST API + WebSocket endpoints
  - JWT authentication
  - MQTT client integration

- **Database** (PostgreSQL)
  - User accounts & authentication
  - Device registry
  - Piston states & history
  - Telemetry data

- **Message Broker** (Mosquitto MQTT)
  - Device communication
  - Command/control messages
  - Status updates

## 🚀 Quick Start

### Prerequisites

**For Backend:**
- Docker & Docker Compose
- OpenSSL (for certificate generation)
- Python 3.8+ (for device client/simulator)

**For Android App:**
- Android Studio Hedgehog or later
- JDK 11+
- Android SDK 36
- See [Mobile App README](../piston-control-mobile/MyApplicationV10/README.md) for details
### Installation
1. **Clone the repository**
```bash
git clone https://github.com/yourusername/piston-control-system.git
cd piston-control-system
````

2. **Generate certificates**
```bash
chmod +x generate-certs.sh
./generate-certs.sh
```

3. **Configure environment**
```bash
cp .env.example .env
# Edit .env with your secure passwords
nano .env
```

4. **Start services**
```bash
docker-compose build
docker-compose up -d
```

5. **Verify deployment**
```bash
curl http://localhost:8080/health
```

6. **Setup Mobile App (Optional)**
```bash
cd ../piston-control-mobile/MyApplicationV10
# Open in Android Studio or build with Gradle
./gradlew build
```
Configure the backend URL in the mobile app's `Constants.kt` file to point to your server.

## 📖 API Documentation

### Authentication
**Register**
```bash
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Login**
```bash
POST /auth/login
Content-Type: application/json

{
  "email": "user@example.com",
  "password": "securepassword"
}
```

### Device Control
**Get Devices**
```bash
GET /devices
Authorization: Bearer <token>
```

**Control Piston**
```bash
POST /devices/{deviceId}/pistons/{pistonNumber}
Authorization: Bearer <token>
Content-Type: application/json

{
  "action": "activate",
  "piston_number": 3
}
```

## 🔐 Security

### Backend Security
- All MQTT communication supports TLS encryption
- JWT tokens for API authentication
- Certificate-based device authentication
- Environment-based secrets management
- **⚠️ Change default passwords in production!**

### Mobile App Security
- JWT token-based authentication
- Encrypted SharedPreferences for token storage (AndroidX Security Crypto)
- Auth interceptor for automatic token injection
- Network Security Config enforcing HTTPS (development exceptions allowed)
- No password storage on device

## 📁 Project Structure

```
.
├── backend/              # Ktor backend (Kotlin)
│   ├── src/
│   │   └── main/kotlin/  # Application source code
│   ├── build.gradle.kts
│   └── Dockerfile
├── mosquitto/            # MQTT broker config
│   └── config/
├── nginx/                # Reverse proxy config
│   └── nginx.conf
├── esp32/                # ESP32 device firmware
│   └── device_client/
├── certs/                # SSL/TLS certificates
├── scripts/              # Utility scripts
├── testing/              # Test scripts and tools
├── docker-compose.yml    # Container orchestration
├── init-db.sql          # Database schema
└── README.md            # This file
```

### Mobile Application (Separate Repository Path)
```
../piston-control-mobile/MyApplicationV10/
├── app/
│   ├── src/main/java/com/example/myapplicationv10/
│   │   ├── model/         # Data models
│   │   ├── network/       # API client & interceptors
│   │   ├── repository/    # Data repositories
│   │   ├── viewmodel/     # ViewModels (MVVM)
│   │   ├── websocket/     # WebSocket manager
│   │   ├── utils/         # Utilities & constants
│   │   └── *.kt          # Activity files
│   └── build.gradle.kts
└── README.md            # Mobile app documentation
```

## 🛠️ Technology Stack

### Backend Infrastructure
- **Backend Framework**: Ktor 2.3 (Kotlin)
- **Database**: PostgreSQL 15
- **MQTT Broker**: Eclipse Mosquitto 2.0
- **Reverse Proxy**: Nginx
- **Containerization**: Docker & Docker Compose
- **Device Client**: Python 3 + paho-mqtt / ESP32 firmware

### Mobile Application
- **Language**: Kotlin
- **Architecture**: MVVM with Repository pattern
- **Async**: Kotlin Coroutines
- **Networking**: Retrofit 2.9.0 + OkHttp 4.12.0
- **WebSocket**: Custom WebSocket implementation
- **Charts**: MPAndroidChart v3.1.0
- **Security**: AndroidX Security Crypto (Encrypted SharedPreferences)
- **Min SDK**: 24 (Android 7.0)
- **Target SDK**: 36

## 📊 Database Schema

- **users** - User accounts and authentication
- **devices** - Registered IoT devices
- **pistons** - Individual piston states (8 per device)
- **telemetry** - Historical event logging

## 📱 Mobile Application

The Android mobile application provides a comprehensive interface for monitoring and controlling your piston systems:

### Features
- **User Authentication** - Secure login/registration with JWT tokens
- **Real-time Dashboard** - Live device status with WebSocket updates
- **Valve Management** - Individual piston control (activate/deactivate)
- **Statistics & Analytics** - Visual charts showing usage patterns
- **History Tracking** - Complete audit trail of all operations
- **Profile Management** - View and edit user profiles
- **Offline Handling** - Graceful degradation when network is unavailable

### Quick Start
1. Open the mobile app project in Android Studio:
   ```bash
   cd ../piston-control-mobile/MyApplicationV10
   ```

2. Configure the backend URL in `app/src/main/java/com/example/myapplicationv10/utils/Constants.kt`:
   ```kotlin
   const val BASE_URL = "http://YOUR_SERVER_IP:8080/"
   const val WEBSOCKET_URL = "ws://YOUR_SERVER_IP:8080/ws"
   ```

3. Build and run:
   ```bash
   ./gradlew build
   ```

For detailed mobile app documentation, see the [Mobile App README](../piston-control-mobile/MyApplicationV10/README.md).

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Contact

**Mohamed Yassine Kaibi**
- LinkedIn: [https://www.linkedin.com/in/mohamedyassinekaibi/](https://www.linkedin.com/in/mohamedyassinekaibi/)

## 🙏 Acknowledgments

- [Ktor](https://ktor.io/) - Kotlin web framework
- [Mosquitto](https://mosquitto.org/) - MQTT broker
- [Exposed](https://github.com/JetBrains/Exposed) - Kotlin SQL framework