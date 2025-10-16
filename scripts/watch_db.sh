#!/bin/bash
while true; do
    clear
    echo "=== PISTON STATES ==="
    docker compose exec -T postgres psql -U piston_user -d piston_control -c "
    SELECT piston_number, state, last_triggered 
    FROM pistons 
    WHERE device_id = '550e8400-e29b-41d4-a716-446655440000'
    ORDER BY piston_number;" 2>/dev/null
    
    echo ""
    echo "=== RECENT TELEMETRY ==="
    docker compose exec -T postgres psql -U piston_user -d piston_control -c "
    SELECT event_type, created_at 
    FROM telemetry 
    WHERE device_id = '550e8400-e29b-41d4-a716-446655440000'
    ORDER BY created_at DESC 
    LIMIT 5;" 2>/dev/null
    
    sleep 2
done
