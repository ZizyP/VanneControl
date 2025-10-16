#!/bin/bash
# Simplified IoT System Monitor

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              IoT System Monitor                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "1. 🔍 Decode MQTT messages (recommended)"
echo "2. 🗄️  Watch database changes"
echo "3. 📋 View backend logs"
echo "4. 🤖 Run device simulator"
echo "5. 🔧 Run diagnostics"
echo "6. 🧪 Run tests"
echo ""
read -p "Choose (1-6): " choice
echo ""

case $choice in
    1)
        echo "Starting MQTT decoder..."
        python3 scripts/mqtt_message_decoder.py
        ;;
    2)
        echo "Watching database (Ctrl+C to stop)..."
        watch -n 2 'docker compose exec -T postgres psql -U piston_user -d piston_control -c "SELECT LEFT(id::text,8) as id, name, status FROM devices; SELECT name, piston_number, state FROM pistons JOIN devices ON pistons.device_id=devices.id WHERE state='\''active'\'';"'
        ;;
    3)
        echo "Showing backend logs (Ctrl+C to stop)..."
        docker compose logs -f backend
        ;;
    4)
        echo "Starting device simulator..."
        python3 scripts/binary_device_client.py
        ;;
    5)
        echo "Running diagnostics..."
        ./scripts/diagnose-and-fix.sh
        ;;
    6)
        echo "Running E2E tests..."
        ./testing/e2e-test.sh
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
