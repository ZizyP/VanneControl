#!/bin/bash
set -e

echo "🚀 Building Piston Control System..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Generate certificates if they don't exist
if [ ! -f certs/ca.crt ]; then
    echo "📜 Generating certificates..."
    ./generate-certs.sh
fi

# Build Docker images
echo "🐳 Building Docker images..."
docker-compose build --parallel

# Create necessary directories
mkdir -p mosquitto/{data,log}
chmod -R 777 mosquitto/{data,log}

# Start services
echo "🎬 Starting services..."
docker-compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check service health
docker-compose ps

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Service URLs:"
echo "  - Backend API: http://localhost:8080"
echo "  - MQTT (Plain): mqtt://localhost:1883"
echo "  - MQTT (TLS): mqtts://localhost:8883"
echo "  - PostgreSQL: postgresql://localhost:5432/piston_control"
echo "  - Redis: redis://localhost:6379"
echo ""
echo "🔐 Default admin credentials:"
echo "  Email: admin@pistoncontrol.local"
echo "  Password: admin123"
echo "  ⚠️  CHANGE THIS IMMEDIATELY!"
echo ""
echo "📝 Next steps:"
echo "  1. Test the API: ./test-api.sh"
echo "  2. Check logs: docker-compose logs -f"
echo "  3. Configure Raspberry Pi devices"
echo ""
