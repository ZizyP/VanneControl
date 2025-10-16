#!/bin/bash

# Quick database query tool
# Usage: ./query-db.sh [table|custom-query]

DB_USER="piston_user"
DB_NAME="piston_control"

query() {
    docker compose exec -T postgres psql -U $DB_USER -d $DB_NAME \
        --pset=border=2 \
        --pset=linestyle=unicode \
        -c "$1" 2>/dev/null
}

if [ $# -eq 0 ]; then
    echo "🔍 Quick Database Query Tool"
    echo ""
    echo "Usage: ./query-db.sh [option]"
    echo ""
    echo "Options:"
    echo "  users          - Show all users"
    echo "  devices        - Show all devices"
    echo "  pistons        - Show all pistons"
    echo "  telemetry      - Show recent telemetry (last 20)"
    echo "  active         - Show all active pistons"
    echo "  device <name>  - Show specific device with pistons"
    echo "  sql <query>    - Run custom SQL query"
    echo ""
    echo "Examples:"
    echo "  ./query-db.sh users"
    echo "  ./query-db.sh device 'Test'"
    echo "  ./query-db.sh sql 'SELECT COUNT(*) FROM devices'"
    echo ""
    exit 0
fi

case "$1" in
    users)
        echo "👥 All Users:"
        query "SELECT id, email, role, created_at FROM users ORDER BY created_at DESC;"
        ;;
    
    devices)
        echo "📟 All Devices:"
        query "
        SELECT 
            LEFT(id::text, 8) || '...' as id,
            name,
            mqtt_client_id,
            status,
            created_at
        FROM devices 
        ORDER BY created_at DESC;
        "
        ;;
    
    pistons)
        echo "🔧 All Pistons:"
        query "
        SELECT 
            d.name as device,
            p.piston_number,
            p.state,
            p.last_triggered
        FROM pistons p
        JOIN devices d ON p.device_id = d.id
        ORDER BY d.name, p.piston_number;
        "
        ;;
    
    telemetry)
        echo "📊 Recent Telemetry (last 20):"
        query "
        SELECT 
            t.id,
            d.name as device,
            t.event_type,
            t.payload,
            t.created_at
        FROM telemetry t
        JOIN devices d ON t.device_id = d.id
        ORDER BY t.created_at DESC
        LIMIT 20;
        "
        ;;
    
    active)
        echo "🔴 Active Pistons:"
        query "
        SELECT 
            d.name as device,
            p.piston_number,
            p.last_triggered
        FROM pistons p
        JOIN devices d ON p.device_id = d.id
        WHERE p.state = 'active'
        ORDER BY d.name, p.piston_number;
        "
        ;;
    
    device)
        if [ -z "$2" ]; then
            echo "Usage: ./query-db.sh device <name>"
            exit 1
        fi
        echo "📟 Device: $2"
        query "
        SELECT 
            d.id,
            d.name,
            d.mqtt_client_id,
            d.status,
            p.piston_number,
            p.state,
            p.last_triggered
        FROM devices d
        LEFT JOIN pistons p ON d.id = p.device_id
        WHERE d.name LIKE '%$2%'
        ORDER BY p.piston_number;
        "
        ;;
    
    sql)
        if [ -z "$2" ]; then
            echo "Usage: ./query-db.sh sql 'YOUR QUERY'"
            exit 1
        fi
        echo "📝 Custom Query:"
        query "$2"
        ;;
    
    *)
        echo "❌ Unknown option: $1"
        echo "Run './query-db.sh' for help"
        exit 1
        ;;
esac
