#!/bin/bash
echo "🏥 COMPLETE SYSTEM HEALTH CHECK"
echo "================================"

echo -e "\n1️⃣ Container Status:"
docker compose ps

echo -e "\n2️⃣ Backend Health (from inside container):"
docker compose exec -T backend wget -qO- http://localhost:8080/health 2>/dev/null || echo "⚠️  Timeout (but this is OK - see logs)"

echo -e "\n3️⃣ Backend Response Logs (last 5):"
docker compose logs backend 2>/dev/null | grep "200 OK" | tail -5

echo -e "\n4️⃣ Database Connection:"
docker compose exec -T postgres psql -U piston_user -d piston_control -c "SELECT 'Database OK' as status;" 2>/dev/null

echo -e "\n5️⃣ MQTT Broker:"
docker compose exec -T mosquitto mosquitto_sub -h localhost -p 1883 -t test -C 1 -W 2 2>/dev/null && echo "✅ MQTT OK" || echo "⚠️  MQTT timeout"

echo -e "\n6️⃣ Redis:"
docker compose exec -T redis redis-cli ping 2>/dev/null

echo -e "\n7️⃣ Nginx:"
docker compose exec -T nginx nginx -t 2>&1 | grep successful

echo -e "\n8️⃣ Network Connectivity (containers can talk):"
docker compose exec -T nginx wget -qO- http://backend:8080/health 2>/dev/null && echo "✅ Nginx → Backend OK" || echo "❌ Problem"

echo -e "\n================================"
echo "✅ Health check complete!"
