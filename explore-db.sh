#!/bin/bash

echo "🗄️  PostgreSQL Database Explorer"
echo "================================"
echo ""

# Database connection details
DB_CONTAINER="piston-postgres"
DB_NAME="piston_control"
DB_USER="piston_user"

# Check if container is running
if ! docker compose ps postgres | grep -q "Up"; then
    echo "❌ PostgreSQL container is not running"
    echo "   Start it with: docker compose up -d postgres"
    exit 1
fi

echo "✅ Connected to database: $DB_NAME"
echo ""

# Function to run SQL queries
query() {
    docker compose exec -T postgres psql -U $DB_USER -d $DB_NAME -c "$1" 2>/dev/null
}

# Function to run SQL and format as table
query_table() {
    docker compose exec -T postgres psql -U $DB_USER -d $DB_NAME \
        -c "$1" \
        --pset=border=2 \
        --pset=linestyle=unicode 2>/dev/null
}

# ═══════════════════════════════════════════════════════════
# OVERVIEW
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DATABASE OVERVIEW"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "📊 Database Size:"
query "SELECT pg_size_pretty(pg_database_size('$DB_NAME')) as size;"
echo ""

echo "📋 All Tables:"
query_table "
SELECT 
    schemaname as schema,
    tablename as table_name,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;
"
echo ""

# ═══════════════════════════════════════════════════════════
# TABLE DETAILS
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TABLE: users"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Schema:"
query_table "
SELECT 
    column_name, 
    data_type, 
    character_maximum_length,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'users'
ORDER BY ordinal_position;
"
echo ""

echo "Row Count:"
query "SELECT COUNT(*) as total_users FROM users;"
echo ""

echo "Data (hiding password_hash):"
query_table "
SELECT 
    id,
    email,
    role,
    LEFT(password_hash, 10) || '...' as password_hash,
    created_at,
    updated_at
FROM users 
ORDER BY created_at DESC 
LIMIT 10;
"
echo ""

# ═══════════════════════════════════════════════════════════
# DEVICES
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TABLE: devices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Schema:"
query_table "
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'devices'
ORDER BY ordinal_position;
"
echo ""

echo "Row Count:"
query "SELECT COUNT(*) as total_devices FROM devices;"
echo ""

echo "Data:"
query_table "
SELECT 
    LEFT(id::text, 8) || '...' as id,
    name,
    LEFT(owner_id::text, 8) || '...' as owner_id,
    mqtt_client_id,
    status,
    created_at
FROM devices 
ORDER BY created_at DESC 
LIMIT 10;
"
echo ""

echo "Devices by Status:"
query_table "
SELECT 
    status, 
    COUNT(*) as count 
FROM devices 
GROUP BY status;
"
echo ""

# ═══════════════════════════════════════════════════════════
# PISTONS
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TABLE: pistons"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Row Count:"
query "SELECT COUNT(*) as total_pistons FROM pistons;"
echo ""

echo "Sample Data:"
query_table "
SELECT 
    LEFT(id::text, 8) || '...' as id,
    LEFT(device_id::text, 8) || '...' as device_id,
    piston_number,
    state,
    last_triggered
FROM pistons 
ORDER BY device_id, piston_number
LIMIT 20;
"
echo ""

echo "Pistons by State:"
query_table "
SELECT 
    state, 
    COUNT(*) as count 
FROM pistons 
GROUP BY state;
"
echo ""

echo "Pistons per Device:"
query_table "
SELECT 
    d.name as device_name,
    COUNT(p.id) as piston_count,
    SUM(CASE WHEN p.state = 'active' THEN 1 ELSE 0 END) as active,
    SUM(CASE WHEN p.state = 'inactive' THEN 1 ELSE 0 END) as inactive
FROM devices d
LEFT JOIN pistons p ON d.id = p.device_id
GROUP BY d.id, d.name
ORDER BY d.name;
"
echo ""

# ═══════════════════════════════════════════════════════════
# TELEMETRY
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TABLE: telemetry"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Row Count:"
query "SELECT COUNT(*) as total_events FROM telemetry;"
echo ""

echo "Events by Type:"
query_table "
SELECT 
    event_type, 
    COUNT(*) as count 
FROM telemetry 
GROUP BY event_type
ORDER BY count DESC;
"
echo ""

echo "Recent Events (last 10):"
query_table "
SELECT 
    id,
    LEFT(device_id::text, 8) || '...' as device_id,
    event_type,
    LEFT(payload, 30) || '...' as payload,
    created_at
FROM telemetry 
ORDER BY created_at DESC 
LIMIT 10;
"
echo ""

# ═══════════════════════════════════════════════════════════
# AUTH TOKENS
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TABLE: auth_tokens"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Row Count:"
query "SELECT COUNT(*) as total_tokens FROM auth_tokens;"
echo ""

echo "Active vs Expired:"
query_table "
SELECT 
    CASE 
        WHEN expires_at > NOW() THEN 'Active'
        ELSE 'Expired'
    END as status,
    COUNT(*) as count
FROM auth_tokens 
GROUP BY status;
"
echo ""

# ═══════════════════════════════════════════════════════════
# RELATIONSHIPS
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "RELATIONSHIPS & JOINS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Users with their Devices:"
query_table "
SELECT 
    u.email,
    COUNT(d.id) as device_count,
    STRING_AGG(d.name, ', ') as device_names
FROM users u
LEFT JOIN devices d ON u.id = d.owner_id
GROUP BY u.id, u.email
ORDER BY device_count DESC;
"
echo ""

echo "Complete Device Overview (with pistons):"
query_table "
SELECT 
    d.name as device,
    d.status,
    d.mqtt_client_id,
    COUNT(p.id) as total_pistons,
    SUM(CASE WHEN p.state = 'active' THEN 1 ELSE 0 END) as active_pistons,
    d.created_at
FROM devices d
LEFT JOIN pistons p ON d.id = p.device_id
GROUP BY d.id, d.name, d.status, d.mqtt_client_id, d.created_at
ORDER BY d.created_at DESC;
"
echo ""

# ═══════════════════════════════════════════════════════════
# USEFUL QUERIES
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "INDEXES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

query_table "
SELECT 
    tablename,
    indexname,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
"
echo ""

# ═══════════════════════════════════════════════════════════
# INTERACTIVE MODE OPTION
# ═══════════════════════════════════════════════════════════

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DONE! Database exploration complete."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Useful Commands:"
echo ""
echo "1. Interactive SQL shell:"
echo "   docker compose exec postgres psql -U $DB_USER -d $DB_NAME"
echo ""
echo "2. Run a custom query:"
echo "   docker compose exec postgres psql -U $DB_USER -d $DB_NAME \\"
echo "     -c \"SELECT * FROM devices WHERE status='online';\""
echo ""
echo "3. Export data to CSV:"
echo "   docker compose exec -T postgres psql -U $DB_USER -d $DB_NAME \\"
echo "     -c \"COPY devices TO STDOUT WITH CSV HEADER;\" > devices.csv"
echo ""
echo "4. Backup database:"
echo "   docker compose exec -T postgres pg_dump -U $DB_USER $DB_NAME > backup.sql"
echo ""
echo "5. View specific device with all pistons:"
echo "   docker compose exec postgres psql -U $DB_USER -d $DB_NAME \\"
echo "     -c \"SELECT d.name, p.piston_number, p.state FROM devices d \\"
echo "     JOIN pistons p ON d.id = p.device_id WHERE d.name LIKE '%Test%';\""
echo ""

# Ask if user wants interactive mode
read -p "🤔 Open interactive SQL shell? (yes/no): " interactive

if [ "$interactive" = "yes" ]; then
    echo ""
    echo "Opening interactive PostgreSQL shell..."
    echo "Type 'SELECT * FROM users;' to see users, or '\dt' to list tables, or '\q' to quit"
    echo ""
    docker compose exec postgres psql -U $DB_USER -d $DB_NAME
fi
