# 🔧 IoT Piston Control System

A complete self-hosted IoT solution for remotely controlling piston actuators via MQTT. Built with modern technologies for reliability and scalability.

## ✨ Features

- 🔐 **Secure Authentication** - JWT-based user authentication
- 🌐 **REST API** - Full-featured API for device management
- 📡 **MQTT Communication** - Real-time device control via Mosquitto broker
- 🔌 **WebSocket Support** - Live status updates to mobile/web clients
- 📊 **PostgreSQL Database** - Persistent storage for users, devices, and telemetry
- 🐳 **Docker Compose** - One-command deployment
- 📱 **Mobile Ready** - Designed for Kotlin Multiplatform Mobile (KMM)
- 🍓 **Hardware Support** - Raspberry Pi and ESP32 compatible

## 🏗️ Architecture
```
Mobile App (KMM) ←→ Nginx ←→ Ktor Backend ←→ PostgreSQL 
					  ↓ 
				Mosquitto MQTT 
					  ↓
					ESP32
```

## 🚀 Quick Start
### Prerequisites
- Docker & Docker Compose
- OpenSSL (for certificate generation)
- Python 3.8+ (for device client)
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

- All MQTT communication supports TLS encryption
- JWT tokens for API authentication
- Certificate-based device authentication
- Environment-based secrets management
- **⚠️ Change default passwords in production!**

## 📁 Project Structure

```
.
├── backend/              # Ktor backend (Kotlin)
│   ├── src/
│   └── Dockerfile
├── mosquitto/            # MQTT broker config
│   └── config/
├── nginx/                # Reverse proxy config
│   └── nginx.conf
├── raspberry-pi/         # Device client (Python)
│   └── device_client.py
├── certs/                # SSL/TLS certificates
├── docker-compose.yml    # Container orchestration
└── init-db.sql          # Database schema
```

## 🛠️ Technology Stack

- **Backend**: Ktor 2.3 (Kotlin)
- **Database**: PostgreSQL 15
- **MQTT Broker**: Eclipse Mosquitto 2.0
- **Reverse Proxy**: Nginx
- **Cache**: Redis (optional)
- **Device**: Python 3 + paho-mqtt

## 📊 Database Schema

- **users** - User accounts and authentication
- **devices** - Registered IoT devices
- **pistons** - Individual piston states (8 per device)
- **telemetry** - Historical event logging

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Ktor](https://ktor.io/) - Kotlin web framework
- [Mosquitto](https://mosquitto.org/) - MQTT broker
- [Exposed](https://github.com/JetBrains/Exposed) - Kotlin SQL framework