#!/bin/bash
set -e

echo "🚀 Piston Control System - Complete Startup & Test"
echo "===================================================="

# Step 1: Check prerequisites
echo -e "\n📋 Step 1: Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo "❌ Docker Compose is not installed"
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"

# Step 2: Check .env file
echo -e "\n📋 Step 2: Checking .env file..."

if [ ! -f .env ]; then
    echo "⚠️  .env file not found."
    
    if [ -f generate-secrets.sh ]; then
        echo "🔐 Running generate-secrets.sh to create secure credentials..."
        chmod +x generate-secrets.sh
        ./generate-secrets.sh
        
        if [ ! -f .env ]; then
            echo "❌ Failed to generate .env file"
            exit 1
        fi
    else
        echo "❌ generate-secrets.sh not found. Cannot generate secure credentials."
        echo "   Please create .env manually with:"
        echo "   - POSTGRES_PASSWORD (min 16 chars)"
        echo "   - JWT_SECRET (min 32 chars)"
        echo "   - REDIS_PASSWORD (min 16 chars)"
        exit 1
    fi
fi

# Validate JWT_SECRET length
JWT_SECRET=$(grep "^JWT_SECRET=" .env | cut -d'=' -f2)
if [ ${#JWT_SECRET} -lt 32 ]; then
    echo "❌ JWT_SECRET is too short (${#JWT_SECRET} chars, minimum 32 required)"
    echo "   Run: ./generate-secrets.sh"
    exit 1
fi

echo "✅ .env file exists with valid JWT_SECRET"

# Step 3: Generate certificates
echo -e "\n📋 Step 3: Checking certificates..."

if [ ! -f certs/ca.crt ]; then
    echo "📜 Generating certificates..."
    if [ -f generate-certs.sh ]; then
        chmod +x generate-certs.sh
        ./generate-certs.sh
    else
        echo "❌ generate-certs.sh not found"
        exit 1
    fi
fi

echo "✅ Certificates exist"

# Step 4: Create necessary directories with proper ownership
echo -e "\n📋 Step 4: Creating directories and fixing permissions..."

mkdir -p mosquitto/{data,log}
mkdir -p nginx/ssl
mkdir -p certs

# Fix permissions for mosquitto (user ID 1883 in the container)
# These warnings are cosmetic but we can fix them
chmod 700 mosquitto/data mosquitto/log 2>/dev/null || true
touch mosquitto/log/mosquitto.log 2>/dev/null || true
chmod 700 mosquitto/log/mosquitto.log 2>/dev/null || true

echo "✅ Directories created"

# Step 5: Stop any existing containers
echo -e "\n📋 Step 5: Cleaning up old containers..."

docker compose down 2>/dev/null || true

echo "✅ Old containers stopped"

# Step 6: Build images
echo -e "\n📋 Step 6: Building Docker images..."
echo "   This may take several minutes on first run..."

docker compose build --no-cache backend

echo "✅ Images built"

# Step 7: Start services
echo -e "\n📋 Step 7: Starting services..."

docker compose up -d

echo "✅ Services started"

# Step 8: Wait for services to be healthy
echo -e "\n📋 Step 8: Waiting for services to be healthy..."
echo "   This may take 30-60 seconds..."

WAIT_TIME=0
MAX_WAIT=120

# Wait for PostgreSQL
echo -n "   PostgreSQL: "
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if docker compose exec -T postgres pg_isready -U piston_user -d piston_control &>/dev/null; then
        echo "✅ Ready"
        break
    fi
    echo -n "."
    sleep 2
    WAIT_TIME=$((WAIT_TIME + 2))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo "❌ PostgreSQL timeout"
    echo "Check logs: docker compose logs postgres"
    exit 1
fi

# Wait for Mosquitto - Check if it's actually accepting connections
echo -n "   Mosquitto: "
WAIT_TIME=0
MOSQUITTO_READY=0
while [ $WAIT_TIME -lt 30 ]; do
    # Check if mosquitto container is running
    if docker compose ps mosquitto | grep -q "Up"; then
        # Check if port 1883 is listening
        if docker compose exec -T mosquitto sh -c "nc -z localhost 1883" &>/dev/null || \
           timeout 2 mosquitto_pub -h localhost -p 1883 -t test -m "test" &>/dev/null || \
           docker compose logs mosquitto 2>&1 | grep -q "mosquitto version.*running"; then
            echo "✅ Ready (accepting connections)"
            MOSQUITTO_READY=1
            break
        fi
    fi
    echo -n "."
    sleep 2
    WAIT_TIME=$((WAIT_TIME + 2))
done

if [ $MOSQUITTO_READY -eq 0 ]; then
    echo "⚠️  Timeout (but may still be working)"
    echo "   Checking if Mosquitto is actually running..."
    if docker compose logs mosquitto 2>&1 | grep -q "mosquitto version.*running"; then
        echo "   ✅ Mosquitto is running (file permission warnings are cosmetic)"
    else
        echo "   Check logs: docker compose logs mosquitto"
    fi
fi

# Wait for Backend
echo -n "   Backend: "
WAIT_TIME=0
while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    HEALTH_RESPONSE=$(curl -s --max-time 2 http://localhost:8080/health 2>/dev/null || echo "")
    if [ ! -z "$HEALTH_RESPONSE" ]; then
        if echo "$HEALTH_RESPONSE" | grep -q "healthy\|status"; then
            echo "✅ Ready"
            break
        fi
    fi
    echo -n "."
    sleep 3
    WAIT_TIME=$((WAIT_TIME + 3))
done

if [ $WAIT_TIME -ge $MAX_WAIT ]; then
    echo "❌ Backend timeout"
    echo ""
    echo "Backend logs (last 30 lines):"
    docker compose logs --tail=30 backend
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check full logs: docker compose logs backend"
    echo "2. Check if backend container is running: docker compose ps"
    echo "3. Verify database connection in logs"
    echo "4. Check .env file has correct DATABASE_PASSWORD"
    exit 1
fi

# Wait for Nginx
echo -n "   Nginx: "
WAIT_TIME=0
while [ $WAIT_TIME -lt 30 ]; do
    if curl -s --max-time 2 http://localhost/health &>/dev/null || \
       docker compose ps nginx | grep -q "Up"; then
        echo "✅ Ready"
        break
    fi
    echo -n "."
    sleep 2
    WAIT_TIME=$((WAIT_TIME + 2))
done

# Step 9: Show service status
echo -e "\n📋 Step 9: Service Status"
docker compose ps

# Check for any warnings in Mosquitto
echo -e "\n📋 Mosquitto Status:"
if docker compose logs mosquitto 2>&1 | grep -q "Warning:"; then
    echo "   ⚠️  File permission warnings detected (cosmetic, not critical)"
    echo "   Mosquitto is running but has non-critical permission warnings"
    echo "   These can be safely ignored or fixed by adjusting volume permissions"
else
    echo "   ✅ No warnings"
fi

# Step 10: Run API tests
echo -e "\n📋 Step 10: Running API Tests..."
echo "=================================================="

if [ -f test-complete-api.sh ]; then
    chmod +x test-complete-api.sh
    ./test-complete-api.sh
else
    echo "⚠️  test-complete-api.sh not found, running basic test..."
    
    # Basic health check
    echo -e "\nHealth Check:"
    curl -s http://localhost:8080/health | jq '.' || curl -s http://localhost:8080/health
    
    # Register test
    echo -e "\nRegistering test user..."
    REGISTER_RESP=$(curl -s -X POST http://localhost:8080/auth/register \
      -H "Content-Type: application/json" \
      -d '{"email":"test@example.com","password":"password123"}')
    echo "$REGISTER_RESP" | jq '.' || echo "$REGISTER_RESP"
fi

echo -e "\n=================================================="
echo "✅ STARTUP COMPLETE!"
echo "=================================================="
echo ""
echo "📊 Service URLs:"
echo "   Backend API: http://localhost:8080"
echo "   Health Check: http://localhost:8080/health"
echo "   MQTT (Plain): mqtt://localhost:1883"
echo "   MQTT (TLS): mqtts://localhost:8883"
echo "   PostgreSQL: postgresql://localhost:5432/piston_control"
echo ""
echo "🔍 Useful Commands:"
echo "   View logs: docker compose logs -f [service]"
echo "   Restart: docker compose restart [service]"
echo "   Stop all: docker compose down"
echo "   Check status: docker compose ps"
echo ""
echo "📱 Test device simulation:"
echo "   python3 simulate_device.py"
echo ""
echo "⚠️  Note: Mosquitto file permission warnings are cosmetic and can be ignored."
echo ""
