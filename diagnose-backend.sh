#!/bin/bash

echo "🔍 Backend Diagnostic Tool"
echo "=========================="

# Check if backend container is running
echo -e "\n1️⃣ Container Status:"
docker compose ps backend

# Check environment variables
echo -e "\n2️⃣ Environment Variables in Container:"
echo "DATABASE_URL:"
docker compose exec -T backend sh -c 'echo $DATABASE_URL' 2>/dev/null || echo "   ❌ Cannot access container"

echo "DATABASE_USER:"
docker compose exec -T backend sh -c 'echo $DATABASE_USER' 2>/dev/null || echo "   ❌ Cannot access container"

echo "MQTT_BROKER:"
docker compose exec -T backend sh -c 'echo $MQTT_BROKER' 2>/dev/null || echo "   ❌ Cannot access container"

echo "JWT_SECRET (length):"
JWT_LEN=$(docker compose exec -T backend sh -c 'echo ${#JWT_SECRET}' 2>/dev/null)
if [ ! -z "$JWT_LEN" ]; then
    echo "   $JWT_LEN characters"
else
    echo "   ❌ Cannot access"
fi

# Check full backend logs for errors
echo -e "\n3️⃣ Backend Startup Logs (first 50 lines):"
docker compose logs backend 2>&1 | head -50

echo -e "\n4️⃣ Backend Error Logs (searching for errors):"
docker compose logs backend 2>&1 | grep -i "error\|exception\|failed\|caused by" | head -20

# Check database connectivity from backend
echo -e "\n5️⃣ Database Connectivity Test:"
docker compose exec -T backend sh -c 'wget -qO- --timeout=2 http://postgres:5432 2>&1' || echo "   Testing database connection..."

# Check if application.conf exists
echo -e "\n6️⃣ Application Configuration:"
docker compose exec -T backend sh -c 'ls -la /app/' 2>/dev/null || echo "   ❌ Cannot access container filesystem"

echo -e "\n7️⃣ JAR File Check:"
docker compose exec -T backend sh -c 'ls -lh /app/*.jar' 2>/dev/null || echo "   ❌ Cannot find JAR file"

# Check if port 8080 is listening
echo -e "\n8️⃣ Port Status (inside container):"
docker compose exec -T backend sh -c 'netstat -tlnp 2>/dev/null | grep 8080' 2>/dev/null || \
docker compose exec -T backend sh -c 'ss -tlnp 2>/dev/null | grep 8080' 2>/dev/null || \
echo "   Port not listening or cannot check"

# Get the actual startup error
echo -e "\n9️⃣ Startup Error Details (last 100 lines):"
docker compose logs backend 2>&1 | tail -100

echo -e "\n🔍 Analysis:"
echo "============"

# Check if container keeps restarting
RESTART_COUNT=$(docker inspect piston-backend --format='{{.RestartCount}}' 2>/dev/null || echo "0")
echo "Container restart count: $RESTART_COUNT"

if [ "$RESTART_COUNT" -gt "0" ]; then
    echo "⚠️  Container is restarting - indicates a crash on startup"
fi

# Check container exit code
EXIT_CODE=$(docker inspect piston-backend --format='{{.State.ExitCode}}' 2>/dev/null || echo "unknown")
echo "Last exit code: $EXIT_CODE"

echo -e "\n💡 Common Issues:"
echo "   • Missing or invalid JWT_SECRET in .env"
echo "   • Database connection failure (wrong password)"
echo "   • MQTT broker not accessible"
echo "   • Missing application.conf in JAR"
echo "   • Kotlin/Java runtime error"
echo ""
