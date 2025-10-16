#!/bin/bash
set -e

echo "🔐 Generating Secure Secrets for .env"
echo "======================================"

# Function to generate a random string
generate_secret() {
    local length=$1
    openssl rand -base64 $length | tr -d "=+/" | cut -c1-$length
}

# Check if .env already exists
if [ -f .env ]; then
    echo ""
    echo "⚠️  .env file already exists!"
    echo ""
    read -p "Do you want to regenerate secrets? This will UPDATE your .env file. (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "❌ Cancelled. Your existing .env file was not modified."
        exit 0
    fi
    
    # Backup existing .env
    backup_file=".env.backup.$(date +%Y%m%d_%H%M%S)"
    cp .env "$backup_file"
    echo "✅ Backed up existing .env to: $backup_file"
fi

echo ""
echo "🎲 Generating cryptographically secure secrets..."

# Generate secrets
POSTGRES_PASSWORD=$(generate_secret 32)
JWT_SECRET=$(generate_secret 64)
REDIS_PASSWORD=$(generate_secret 32)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create or update .env file
cat > .env << EOF
# ========================================
# Piston Control System - Environment Variables
# Generated: $BUILD_DATE
# ========================================

# ────────────────────────────────────────
# PostgreSQL Database Configuration
# ────────────────────────────────────────
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# ────────────────────────────────────────
# JWT Authentication
# ────────────────────────────────────────
# Secret must be at least 32 characters
# Used for signing and verifying JWT tokens
JWT_SECRET=$JWT_SECRET

# ────────────────────────────────────────
# Redis Cache (Optional)
# ────────────────────────────────────────
REDIS_PASSWORD=$REDIS_PASSWORD

# ────────────────────────────────────────
# Build Metadata
# ────────────────────────────────────────
BUILD_DATE=$BUILD_DATE
VCS_REF=main

# ────────────────────────────────────────
# Security Notes
# ────────────────────────────────────────
# 🔒 NEVER commit this file to version control
# 🔒 Keep these secrets secure and private
# 🔒 Rotate secrets regularly in production
# 🔒 Use different secrets for dev/staging/prod
EOF

echo ""
echo "✅ Secrets generated successfully!"
echo ""
echo "📝 Summary:"
echo "   • POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:0:8}... (32 chars)"
echo "   • JWT_SECRET:        ${JWT_SECRET:0:8}... (64 chars)"
echo "   • REDIS_PASSWORD:    ${REDIS_PASSWORD:0:8}... (32 chars)"
echo ""
echo "📁 Configuration saved to: .env"
echo ""
echo "⚠️  IMPORTANT SECURITY REMINDERS:"
echo "   1. Never commit .env to git (already in .gitignore)"
echo "   2. Keep .env file permissions restricted: chmod 600 .env"
echo "   3. Use different secrets for production"
echo "   4. Rotate secrets regularly"
echo ""

# Set secure permissions on .env
chmod 600 .env
echo "🔒 Set .env file permissions to 600 (owner read/write only)"
echo ""

# Show what to do next
echo "🚀 Next Steps:"
echo "   1. Review the generated .env file"
echo "   2. Start the system: ./startup-and-test.sh"
echo "   3. (Optional) Customize any settings in .env"
echo ""
