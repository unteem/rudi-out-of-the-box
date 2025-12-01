#!/bin/bash
# update-configs.sh - Update RUDI configuration files with generated passwords
#
# This script updates all configuration files with passwords from .passwords.env
# WARNING: This will modify configuration files in place

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Updating Configuration Files"
echo "========================================="
echo ""

# Check if passwords file exists
if [ ! -f "$ROOT_DIR/.passwords.env" ]; then
  echo "ERROR: .passwords.env not found!"
  echo "Please run generate-passwords.sh first"
  exit 1
fi

# Source passwords
source "$ROOT_DIR/.passwords.env"
source "$ROOT_DIR/.env"

echo "WARNING: This will modify configuration files in place!"
echo "A backup will be created first."
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Create backup
BACKUP_DIR="$ROOT_DIR/config-backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP_DIR"
cp -r "$ROOT_DIR/config" "$BACKUP_DIR"

# Function to update property file
update_property() {
  local file=$1
  local key=$2
  local value=$3
  
  if [ -f "$file" ]; then
    # Escape special characters in value
    escaped_value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    # Update or add property
    if grep -q "^${key}=" "$file"; then
      sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$file"
    else
      echo "${key}=${escaped_value}" >> "$file"
    fi
  fi
}

echo ""
echo "[1/5] Preparing database initialization..."
echo "  ℹ  Database init files will be processed by prepare-database-init.sh"
echo "  ℹ  Using envsubst to replace password variables"

echo ""
echo "[2/5] Docker Compose files use environment variables..."
echo "  ℹ  Variables will be read from .env.local at runtime"
echo "  ℹ  No modification of docker-compose files needed"

echo ""
echo "[3/5] Properties files use envsubst templates..."
echo "  ℹ  Properties will be processed by prepare-properties.sh"
echo "  ℹ  Using envsubst with explicit variable list"
echo "  ℹ  Spring Boot property references will be preserved"

echo ""
echo "[5/5] Creating environment override file..."

# Create .env.local for Docker Compose to use
cat > "$ROOT_DIR/.env.local" << EOF
# Auto-generated environment overrides
# Source: update-configs.sh on $(date)

# Database passwords for Docker Compose
DB_RUDI=${DB_RUDI}
DB_DATAVERSE=${DB_DATAVERSE}
DB_MAGNOLIA=${DB_MAGNOLIA}

# Dataverse
DATAVERSE_API_TOKEN=${DATAVERSE_API_TOKEN}

# Application
EUREKA_PASSWORD=${EUREKA_PASSWORD}
KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}
EOF

chmod 600 "$ROOT_DIR/.env.local"
echo "  ✓ Created .env.local"

echo ""
echo "========================================="
echo "✓ Configuration update complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  - Backup created: $BACKUP_DIR"
echo "  - Prepared database init scripts (envsubst will process)"
echo "  - Docker Compose files use environment variables"
echo "  - Properties files use envsubst templates"
echo "  - Created .env.local for Docker Compose variable resolution"
echo ""
echo "What will be configured:"
echo "  ✓ Database passwords (via envsubst)"
echo "  ✓ OAuth2 client secrets (via envsubst)"
echo "  ✓ Keystore passwords (via envsubst)"
echo "  ✓ Eureka credentials (via envsubst)"
echo "  ✓ Dataverse API token (via envsubst)"
echo "  ✓ Special keystore passwords (via envsubst)"
echo ""
echo "Next steps:"
echo "  1. Run prepare-properties.sh to process templates"
echo "  2. Deploy platform: docker compose up -d"
echo "  3. Verify all services start correctly"
echo "  4. Change application user passwords via UI/database"
echo ""
echo "IMPORTANT:"
echo "  - If deployment fails, restore from backup:"
echo "    rm -rf config && mv $BACKUP_DIR config"
echo ""
